//go:build freebsd

package pf

import (
	"fmt"
	"net"
	"os"
	"sync"
	"unsafe"

	"golang.org/x/sys/unix"
)

const (
	// FreeBSD ioctl definitions for pf table manipulation
	// _IOWR('D', 67, struct pfioc_table) -> 0xc4504443 on 64-bit FreeBSD
	// _IOWR('D', 68, struct pfioc_table) -> 0xc4504444 on 64-bit FreeBSD
	// _IOWR('D', 70, struct pfioc_table) -> 0xc4504446 on 64-bit FreeBSD
	DIOCRADDADDRS = 0xc4504443
	DIOCRDELADDRS = 0xc4504444
	DIOCRGETADDRS = 0xc4504446

	PFR_TABLE_NAME_SIZE = 32
	MAXPATHLEN          = 1024

	AF_INET  = 2
	AF_INET6 = 28
)

// pfr_table matches FreeBSD's struct pfr_table
type pfrTable struct {
	anchor [MAXPATHLEN]byte
	name   [PFR_TABLE_NAME_SIZE]byte
	flags  uint32
	fback  uint8
	_pad   [3]byte
}

// pfr_addr matches FreeBSD's struct pfr_addr
type pfrAddr struct {
	addr  [16]byte // union of in_addr / in6_addr
	af    uint8
	net   uint8
	not   uint8
	fback uint8
	_pad  [4]byte
}

// pfioc_table matches FreeBSD's struct pfioc_table
type pfiocTable struct {
	table   pfrTable
	buffer  uintptr
	esize   int32
	size    int32
	size2   int32
	nadd    int32
	ndel    int32
	nchange int32
	flags   int32
	ticket  uint32
}

// BSDDevice represents a live /dev/pf character device on FreeBSD.
type BSDDevice struct {
	mu sync.Mutex
	fd int
}

// Open opens /dev/pf with O_RDWR. Requires root / wheel permissions.
func Open(devPath string) (Device, error) {
	if devPath == "" {
		devPath = "/dev/pf"
	}

	fd, err := unix.Open(devPath, os.O_RDWR, 0)
	if err != nil {
		return nil, fmt.Errorf("failed to open pf device %s: %w", devPath, err)
	}

	return &BSDDevice{fd: fd}, nil
}

// AddAddresses adds a batch of IP addresses to the given table.
func (d *BSDDevice) AddAddresses(table string, ips []net.IP) (int, error) {
	if len(ips) == 0 {
		return 0, nil
	}

	d.mu.Lock()
	defer d.mu.Unlock()

	if d.fd < 0 {
		return 0, ErrDeviceClosed
	}

	addrs := make([]pfrAddr, len(ips))
	for i, ip := range ips {
		if ip4 := ip.To4(); ip4 != nil {
			copy(addrs[i].addr[:4], ip4)
			addrs[i].af = AF_INET
			addrs[i].net = 32
		} else if ip6 := ip.To16(); ip6 != nil {
			copy(addrs[i].addr[:], ip6)
			addrs[i].af = AF_INET6
			addrs[i].net = 128
		} else {
			return 0, fmt.Errorf("invalid IP: %v", ip)
		}
	}

	var io pfiocTable
	copy(io.table.name[:], table)
	io.buffer = uintptr(unsafe.Pointer(&addrs[0]))
	io.esize = int32(unsafe.Sizeof(addrs[0]))
	io.size = int32(len(addrs))

	_, _, errno := unix.Syscall(unix.SYS_IOCTL, uintptr(d.fd), uintptr(DIOCRADDADDRS), uintptr(unsafe.Pointer(&io)))
	if errno != 0 {
		return 0, fmt.Errorf("DIOCRADDADDRS ioctl failed: %w", errno)
	}

	return int(io.nadd), nil
}

// DelAddresses removes a batch of IP addresses from the given table.
func (d *BSDDevice) DelAddresses(table string, ips []net.IP) (int, error) {
	if len(ips) == 0 {
		return 0, nil
	}

	d.mu.Lock()
	defer d.mu.Unlock()

	if d.fd < 0 {
		return 0, ErrDeviceClosed
	}

	addrs := make([]pfrAddr, len(ips))
	for i, ip := range ips {
		if ip4 := ip.To4(); ip4 != nil {
			copy(addrs[i].addr[:4], ip4)
			addrs[i].af = AF_INET
			addrs[i].net = 32
		} else if ip6 := ip.To16(); ip6 != nil {
			copy(addrs[i].addr[:], ip6)
			addrs[i].af = AF_INET6
			addrs[i].net = 128
		} else {
			return 0, fmt.Errorf("invalid IP: %v", ip)
		}
	}

	var io pfiocTable
	copy(io.table.name[:], table)
	io.buffer = uintptr(unsafe.Pointer(&addrs[0]))
	io.esize = int32(unsafe.Sizeof(addrs[0]))
	io.size = int32(len(addrs))

	_, _, errno := unix.Syscall(unix.SYS_IOCTL, uintptr(d.fd), uintptr(DIOCRDELADDRS), uintptr(unsafe.Pointer(&io)))
	if errno != 0 {
		return 0, fmt.Errorf("DIOCRDELADDRS ioctl failed: %w", errno)
	}

	return int(io.ndel), nil
}

// FlushTable removes every address currently stored in the given table.
//
// It enumerates the table contents with DIOCRGETADDRS and deletes the
// enumerated addresses in batches with DIOCRDELADDRS, repeating until the
// table reports empty. This is used at daemon startup to drop stale entries
// left behind by a previous run: the in-memory TTL heap is lost on restart,
// so without a flush those entries would leak in the kernel table forever
// (the table itself is created with "persist", which survives filter reloads).
//
// Returns the total number of addresses removed. If the table does not exist
// in the kernel, an error wrapping ErrTableNotFound is returned.
func (d *BSDDevice) FlushTable(table string) (int, error) {
	d.mu.Lock()
	defer d.mu.Unlock()

	if d.fd < 0 {
		return 0, ErrDeviceClosed
	}

	// Batch size for one GETADDRS/DELADDRS round trip. pfrAddr is 32 bytes,
	// so one batch costs ~128 KiB of temporary buffer.
	const batchSize = 4096

	total := 0
	for {
		addrs := make([]pfrAddr, batchSize)

		var get pfiocTable
		copy(get.table.name[:], table)
		get.buffer = uintptr(unsafe.Pointer(&addrs[0]))
		get.esize = int32(unsafe.Sizeof(addrs[0]))
		get.size = int32(len(addrs))

		_, _, errno := unix.Syscall(unix.SYS_IOCTL, uintptr(d.fd), uintptr(DIOCRGETADDRS), uintptr(unsafe.Pointer(&get)))
		if errno != 0 {
			if errno == unix.ESRCH {
				return total, fmt.Errorf("table %q: %w", table, ErrTableNotFound)
			}
			return total, fmt.Errorf("DIOCRGETADDRS ioctl failed: %w", errno)
		}

		n := int(get.size)
		if n == 0 {
			break // table is empty
		}

		var del pfiocTable
		copy(del.table.name[:], table)
		del.buffer = uintptr(unsafe.Pointer(&addrs[0]))
		del.esize = int32(unsafe.Sizeof(addrs[0]))
		del.size = int32(n)

		_, _, errno = unix.Syscall(unix.SYS_IOCTL, uintptr(d.fd), uintptr(DIOCRDELADDRS), uintptr(unsafe.Pointer(&del)))
		if errno != 0 {
			if errno == unix.ESRCH {
				return total, fmt.Errorf("table %q: %w", table, ErrTableNotFound)
			}
			return total, fmt.Errorf("DIOCRDELADDRS ioctl failed: %w", errno)
		}
		total += int(del.ndel)

		if n < batchSize {
			break // last partial batch; table is now empty
		}
		// Buffer was full: the table may hold more addresses, enumerate again.
	}

	return total, nil
}

// Close closes the /dev/pf descriptor.
func (d *BSDDevice) Close() error {
	d.mu.Lock()
	defer d.mu.Unlock()

	if d.fd >= 0 {
		err := unix.Close(d.fd)
		d.fd = -1
		return err
	}
	return nil
}

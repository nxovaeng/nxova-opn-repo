package pf

import (
	"errors"
	"net"
)

var (
	ErrDeviceClosed = errors.New("pf device closed")
	ErrInvalidTable = errors.New("invalid table name")
	ErrEmptyIPList  = errors.New("empty IP list")
	// ErrTableNotFound is returned when the requested pf table does not
	// exist in the kernel (ioctl reports ESRCH). Callers that only want to
	// clean up best-effort should treat this as a warning, not a failure.
	ErrTableNotFound = errors.New("pf table not found")
)

// Device represents an interface for Packet Filter table operations.
type Device interface {
	// AddAddresses inserts a batch of IP addresses into the specified table.
	// Returns the number of newly added addresses.
	AddAddresses(table string, ips []net.IP) (int, error)

	// DelAddresses removes a batch of IP addresses from the specified table.
	// Returns the number of addresses removed.
	DelAddresses(table string, ips []net.IP) (int, error)

	// FlushTable removes ALL addresses currently stored in the specified
	// table. Returns the number of addresses removed. If the table does not
	// exist, ErrTableNotFound is returned (wrapped).
	FlushTable(table string) (int, error)

	// Close releases the /dev/pf file descriptor.
	Close() error
}

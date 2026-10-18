//go:build !freebsd

package pf

import (
	"errors"
	"net"
	"testing"
)

func TestMockFlushTable(t *testing.T) {
	dev, err := Open("")
	if err != nil {
		t.Fatalf("Open failed: %v", err)
	}
	defer dev.Close()

	// Flushing a missing table must report ErrTableNotFound.
	if _, err := dev.FlushTable("nope"); !errors.Is(err, ErrTableNotFound) {
		t.Fatalf("expected ErrTableNotFound, got %v", err)
	}

	ips := []net.IP{
		net.ParseIP("192.0.2.1"),
		net.ParseIP("192.0.2.2"),
		net.ParseIP("2001:db8::1"),
	}
	if _, err := dev.AddAddresses("t1", ips); err != nil {
		t.Fatalf("AddAddresses failed: %v", err)
	}

	n, err := dev.FlushTable("t1")
	if err != nil {
		t.Fatalf("FlushTable failed: %v", err)
	}
	if n != len(ips) {
		t.Fatalf("expected %d flushed, got %d", len(ips), n)
	}

	// Table is gone after flush: flushing again reports not-found.
	if _, err := dev.FlushTable("t1"); !errors.Is(err, ErrTableNotFound) {
		t.Fatalf("expected ErrTableNotFound after flush, got %v", err)
	}
}

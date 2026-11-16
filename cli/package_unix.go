//go:build darwin || linux

package main

import (
	"os"

	"golang.org/x/sys/unix"
)

func lockDirectory(path string) (func(), error) {
	directory, err := os.Open(path)
	if err != nil {
		return nil, err
	}
	if err := unix.Flock(int(directory.Fd()), unix.LOCK_EX); err != nil {
		_ = directory.Close()
		return nil, err
	}
	return func() { _ = directory.Close() }, nil
}

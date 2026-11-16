package main

import "golang.org/x/sys/unix"

func installPackage(source, target string, replace bool) error {
	flags := uint(unix.RENAME_NOREPLACE)
	if replace {
		flags = unix.RENAME_EXCHANGE
	}
	return unix.Renameat2(unix.AT_FDCWD, source, unix.AT_FDCWD, target, flags)
}

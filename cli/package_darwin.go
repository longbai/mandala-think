package main

import "golang.org/x/sys/unix"

func installPackage(source, target string, replace bool) error {
	flags := uint32(unix.RENAME_EXCL)
	if replace {
		flags = unix.RENAME_SWAP
	}
	return unix.RenameatxNp(unix.AT_FDCWD, source, unix.AT_FDCWD, target, flags)
}

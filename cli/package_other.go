//go:build !darwin && !linux

package main

import "fmt"

func lockDirectory(string) (func(), error) {
	return nil, fmt.Errorf("atomic package writes require macOS or Linux")
}

func installPackage(string, string, bool) error {
	return fmt.Errorf("atomic package writes require macOS or Linux")
}

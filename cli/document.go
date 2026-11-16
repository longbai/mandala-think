package main

import (
	"fmt"
	"io"
	"os"
	"path/filepath"
	"strings"
)

const usage = `Usage:
  mandala-web-reader [serve] [-listen 127.0.0.1:8080]
  mandala-web-reader new <project.mprj> <title> [center]
  mandala-web-reader read <package>
  mandala-web-reader validate <package>
  mandala-web-reader write [--replace | --backup] <package> [snapshot.yaml | -]
  mandala-web-reader convert [--backup] <source> <destination>
  mandala-web-reader id

Read and validate accept .mprj, .mandalaprj, and legacy .mandala.
Write and convert produce .mprj or .mandalaprj. Write reads YAML from stdin
by default. --replace checks the project ID and revision before updating
an existing .mprj. --backup preserves reminder records and project identity.
Use id to generate a short identifier for a new cell or action.
`

func runDocument(command string, args []string, stdin io.Reader, stdout io.Writer) error {
	switch command {
	case "new":
		if len(args) < 2 || len(args) > 3 || !strings.EqualFold(filepath.Ext(args[0]), ".mprj") ||
			strings.TrimSpace(args[1]) == "" {
			return fmt.Errorf("usage: new <project.mprj> <title> [center]")
		}
		center := ""
		if len(args) == 3 {
			center = args[2]
		}
		p, err := newProject(args[1], center)
		if err != nil {
			return err
		}
		return writePackage(args[0], p, false, false)
	case "read", "validate":
		if len(args) != 1 {
			return fmt.Errorf("usage: %s <package>", command)
		}
		p, err := readPackage(args[0])
		if err != nil {
			return err
		}
		if command == "validate" {
			_, err = fmt.Fprintf(stdout, "Valid project (%d cells)\n", len(p.Cells))
			return err
		}
		data, err := encodeYAML(p)
		if err != nil {
			return err
		}
		if len(data) > 2*maxPackage {
			return fmt.Errorf("snapshot exceeds size limit")
		}
		_, err = stdout.Write(data)
		return err
	case "write":
		return writeSnapshot(args, stdin)
	case "convert":
		return convertPackage(args)
	case "id":
		if len(args) != 0 {
			return fmt.Errorf("usage: id")
		}
		id, err := shortID()
		if err != nil {
			return err
		}
		_, err = fmt.Fprintln(stdout, id)
		return err
	default:
		return fmt.Errorf("unknown command %q; use --help", command)
	}
}

func writeSnapshot(args []string, stdin io.Reader) error {
	replace, backup := false, false
	if len(args) > 0 && oneOf(args[0], "--replace", "--backup") {
		replace, backup = args[0] == "--replace", args[0] == "--backup"
		args = args[1:]
	}
	if len(args) < 1 || len(args) > 2 {
		return fmt.Errorf("usage: write [--replace | --backup] <package> [snapshot.yaml | -]")
	}
	input := stdin
	if len(args) == 2 && args[1] != "-" {
		file, err := os.Open(args[1])
		if err != nil {
			return err
		}
		defer file.Close()
		input = file
	}
	data, err := readLimited(input, 2*maxPackage)
	if err != nil {
		return err
	}
	var p project
	if err := decodeYAML(data, &p); err != nil {
		return fmt.Errorf("invalid YAML snapshot: %w", err)
	}
	return writePackage(args[0], &p, replace, backup)
}

func convertPackage(args []string) error {
	backup := len(args) > 0 && args[0] == "--backup"
	if backup {
		args = args[1:]
	}
	if len(args) != 2 {
		return fmt.Errorf("usage: convert [--backup] <source> <destination>")
	}
	p, err := readPackage(args[0])
	if err != nil {
		return err
	}
	if strings.EqualFold(filepath.Ext(args[1]), ".mprj") {
		if !backup && !strings.EqualFold(filepath.Ext(args[0]), ".mandala") {
			previousID := p.Manifest.ID
			p.Manifest.ID, err = uniqueID(func(id string) bool { return id == previousID })
			if err != nil {
				return err
			}
			previousRevision := p.Manifest.Revision
			p.Manifest.Revision, err = uniqueID(func(id string) bool { return id == previousRevision })
			if err != nil {
				return err
			}
			p.ReminderLinks = nil
		}
		backup = false
	}
	return writePackage(args[1], p, false, backup)
}

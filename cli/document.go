package main

import (
	"flag"
	"fmt"
	"io"
	"os"
	"path/filepath"
	"strings"
)

const usage = `Usage: mandala <command> [flags]

Commands:
  create --title TITLE --output PROJECT.mprj [--center TEXT]
      Create an editable project.
  locate --name NAME
      Print the path of a project in iCloud Drive/MandalaThink on macOS.
  export (--project PATH | --name NAME) --output FILE [--backup]
      Export a YAML snapshot (.yaml, .yml, or -) or a share archive (.mandalaprj).
      --backup preserves reminder records in a share archive.
  apply (--project PATH | --name NAME) --input FILE
      Apply a YAML snapshot to the same .mprj after checking its ID and revision.
  import --input FILE --output PROJECT.mprj [--restore]
      Import a legacy .mandala, .mandalaprj archive, .mprj package, or YAML snapshot.
      --restore keeps the source project's identity and reminder records.
  validate (--project PATH | --name NAME)
      Check a document without editing it.
  generate-id
      Print a short identifier for a new cell or action.
  serve [--listen 127.0.0.1:8080]
      Start the browser reader.

Use --help after a command to see its flags.
Use - as a YAML input or output to read stdin or write stdout.
`

type documentOptions struct {
	project string
	name    string
	input   string
	output  string
	title   string
	center  string
	backup  bool
	restore bool
}

func runDocument(command string, args []string, stdin io.Reader, stdout io.Writer) error {
	var options documentOptions
	flags := flag.NewFlagSet(command, flag.ContinueOnError)
	flags.SetOutput(io.Discard)
	flags.Usage = func() {}
	switch command {
	case "create":
		flags.StringVar(&options.title, "title", "", "Project title (required)")
		flags.StringVar(&options.center, "center", "", "Initial text in the center cell")
		flags.StringVar(&options.output, "output", "", "New .mprj path (required)")
	case "locate":
		flags.StringVar(&options.name, "name", "", "Project name in iCloud Drive/MandalaThink (required)")
	case "export", "apply", "validate":
		flags.StringVar(&options.project, "project", "", "Path to the project")
		flags.StringVar(&options.name, "name", "", "Project name in iCloud Drive/MandalaThink; use instead of --project")
		switch command {
		case "export":
			flags.StringVar(&options.output, "output", "", "New .yaml, .yml, or .mandalaprj path, or - for YAML on stdout (required)")
			flags.BoolVar(&options.backup, "backup", false, "Preserve reminder records in a .mandalaprj archive")
		case "apply":
			flags.StringVar(&options.input, "input", "", "YAML snapshot path, or - for stdin (required)")
		}
	case "import":
		flags.StringVar(&options.input, "input", "", "Source .mandala, .mandalaprj, .mprj, YAML path, or - for YAML on stdin (required)")
		flags.StringVar(&options.output, "output", "", "New .mprj path (required)")
		flags.BoolVar(&options.restore, "restore", false, "Keep the source project ID and reminder records")
	case "generate-id":
	default:
		return fmt.Errorf("unknown command %q; use mandala --help", command)
	}

	if err := flags.Parse(args); err == flag.ErrHelp {
		fmt.Fprintf(stdout, "Usage: mandala %s [flags]\n", command)
		flags.SetOutput(stdout)
		flags.PrintDefaults()
		return nil
	} else if err != nil {
		return fmt.Errorf("%s: %w; see mandala %s --help", command, err, command)
	}
	if flags.NArg() != 0 {
		return fmt.Errorf("%s takes named flags; see mandala %s --help", command, command)
	}

	switch command {
	case "create":
		if strings.TrimSpace(options.title) == "" || !strings.EqualFold(filepath.Ext(options.output), ".mprj") {
			return fmt.Errorf("create requires --title and --output ending in .mprj")
		}
		p, err := newProject(options.title, options.center)
		if err != nil {
			return err
		}
		return writePackage(options.output, p, false, false)
	case "locate":
		if strings.TrimSpace(options.name) == "" {
			return fmt.Errorf("locate requires --name")
		}
		path, err := options.projectPath()
		if err != nil {
			return err
		}
		_, err = fmt.Fprintln(stdout, path)
		return err
	case "export":
		return options.export(stdout)
	case "apply":
		path, err := options.projectPath()
		if err != nil {
			return err
		}
		if !strings.EqualFold(filepath.Ext(path), ".mprj") {
			return fmt.Errorf("apply requires an editable .mprj project")
		}
		p, err := readSnapshot(options.input, stdin)
		if err != nil {
			return err
		}
		return writePackage(path, p, true, false)
	case "import":
		return options.importProject(stdin)
	case "validate":
		path, err := options.projectPath()
		if err != nil {
			return err
		}
		p, err := readPackage(path)
		if err != nil {
			return err
		}
		_, err = fmt.Fprintf(stdout, "Valid project (%d cells)\n", len(p.Cells))
		return err
	default: // generate-id
		id, err := shortID()
		if err != nil {
			return err
		}
		_, err = fmt.Fprintln(stdout, id)
		return err
	}
}

func (options documentOptions) projectPath() (string, error) {
	name := strings.TrimSpace(options.name)
	if (options.project == "") == (name == "") {
		return "", fmt.Errorf("specify exactly one of --project or --name")
	}
	if name == "" {
		return options.project, nil
	}
	home, err := os.UserHomeDir()
	if err != nil {
		return "", err
	}
	directory := filepath.Join(home, "Library", "Mobile Documents", "iCloud~org~mandalathink~app", "Documents")
	return locateProject(directory, name)
}

func locateProject(directory, name string) (string, error) {
	entries, err := os.ReadDir(directory)
	if err != nil {
		return "", fmt.Errorf("open iCloud Drive/MandalaThink: %w", err)
	}
	var matches []string
	for _, entry := range entries {
		extension := filepath.Ext(entry.Name())
		if !entry.IsDir() || strings.HasPrefix(entry.Name(), ".") || !strings.EqualFold(extension, ".mprj") {
			continue
		}
		path := filepath.Join(directory, entry.Name())
		if strings.EqualFold(name, entry.Name()) || strings.EqualFold(name, strings.TrimSuffix(entry.Name(), extension)) {
			matches = append(matches, entry.Name())
			continue
		}
		current, err := readProjectManifest(path)
		if err == nil && current.Title != nil && strings.EqualFold(name, *current.Title) {
			matches = append(matches, entry.Name())
		}
	}
	switch len(matches) {
	case 0:
		return "", fmt.Errorf("project %q was not found in iCloud Drive/MandalaThink", name)
	case 1:
		return filepath.Join(directory, matches[0]), nil
	default:
		return "", fmt.Errorf("project name %q is ambiguous; matching packages: %q", name, matches)
	}
}

func (options documentOptions) export(stdout io.Writer) error {
	extension := strings.ToLower(filepath.Ext(options.output))
	archive := extension == ".mandalaprj"
	if !archive && options.output != "-" && !oneOf(extension, ".yaml", ".yml") {
		return fmt.Errorf("export requires --output ending in .yaml, .yml, or .mandalaprj, or - for stdout")
	}
	if options.backup && !archive {
		return fmt.Errorf("--backup applies to .mandalaprj exports; YAML snapshots already preserve reminder records")
	}
	path, err := options.projectPath()
	if err != nil {
		return err
	}
	p, err := readPackage(path)
	if err != nil {
		return err
	}
	if archive {
		return writePackage(options.output, p, false, options.backup)
	}
	data, err := encodeYAML(p)
	if err != nil {
		return err
	}
	if len(data) > 2*maxPackage {
		return fmt.Errorf("snapshot exceeds size limit")
	}
	if options.output == "-" {
		_, err = stdout.Write(data)
		return err
	}
	return writeSnapshot(options.output, data)
}

func writeSnapshot(path string, data []byte) error {
	file, err := os.OpenFile(path, os.O_WRONLY|os.O_CREATE|os.O_EXCL, 0600)
	if err != nil {
		return err
	}
	_, writeErr := file.Write(data)
	closeErr := file.Close()
	if writeErr != nil || closeErr != nil {
		_ = os.Remove(path)
	}
	if writeErr != nil {
		return writeErr
	}
	return closeErr
}

func readSnapshot(path string, stdin io.Reader) (*project, error) {
	if path == "" {
		return nil, fmt.Errorf("specify --input pointing to a YAML snapshot, or - for stdin")
	}
	input := stdin
	if path != "-" {
		file, err := os.Open(path)
		if err != nil {
			return nil, err
		}
		defer file.Close()
		input = file
	}
	data, err := readLimited(input, 2*maxPackage)
	if err != nil {
		return nil, err
	}
	var p project
	if err := decodeYAML(data, &p); err != nil {
		return nil, fmt.Errorf("invalid YAML snapshot: %w", err)
	}
	return &p, nil
}

func (options documentOptions) importProject(stdin io.Reader) error {
	if options.input == "" || !strings.EqualFold(filepath.Ext(options.output), ".mprj") {
		return fmt.Errorf("import requires --input and --output ending in .mprj")
	}
	extension := strings.ToLower(filepath.Ext(options.input))
	if extension == ".mandala" && options.restore {
		return fmt.Errorf("--restore requires a MandalaThink source with an existing project ID")
	}
	var p *project
	var err error
	if options.input == "-" || oneOf(extension, ".yaml", ".yml") {
		p, err = readSnapshot(options.input, stdin)
	} else {
		p, err = readPackage(options.input)
	}
	if err != nil {
		return err
	}
	if !options.restore && extension != ".mandala" {
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
	return writePackage(options.output, p, false, false)
}

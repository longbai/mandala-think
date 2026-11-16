package main

import (
	"archive/zip"
	"errors"
	"fmt"
	"io"
	"os"
	"path/filepath"
	"sort"
	"strings"
)

func readLimited(r io.Reader, maximum int) ([]byte, error) {
	data, err := io.ReadAll(io.LimitReader(r, int64(maximum)+1))
	if err == nil && len(data) > maximum {
		err = fmt.Errorf("input exceeds the supported size limit")
	}
	return data, err
}

func readPackage(path string) (*project, error) {
	switch strings.ToLower(filepath.Ext(path)) {
	case ".mprj":
		files, err := readDirectory(path)
		if err != nil {
			return nil, err
		}
		return decodePackage(files)
	case ".mandalaprj", ".mandala":
		files, err := readArchive(path)
		if err != nil {
			return nil, err
		}
		if strings.EqualFold(filepath.Ext(path), ".mandala") {
			return importLegacy(filepath.Base(path), files)
		}
		var root string
		records := make(map[string][]byte)
		for name, data := range files {
			folder, relative, _ := strings.Cut(name, "/")
			if !strings.HasSuffix(folder, ".mprj") || root != "" && root != folder {
				return nil, fmt.Errorf("ZIP must contain exactly one .mprj root")
			}
			root = folder
			if data == nil {
				if relative != "" && !oneOf(relative, "cells/", "assets/", "reminder-links/") {
					return nil, fmt.Errorf("invalid package directory %q", name)
				}
				continue
			}
			records[relative] = data
		}
		return decodePackage(records)
	default:
		return nil, fmt.Errorf("unsupported package %q", path)
	}
}

func readDirectory(path string) (map[string][]byte, error) {
	info, err := os.Lstat(path)
	if err != nil {
		return nil, err
	}
	if !info.IsDir() {
		return nil, fmt.Errorf("expected a .mprj directory")
	}
	files := make(map[string][]byte)
	total, entries := maxPackage, 0
	err = filepath.WalkDir(path, func(entryPath string, entry os.DirEntry, walkErr error) error {
		if walkErr != nil || entryPath == path {
			return walkErr
		}
		if entry.Name() == ".DS_Store" && entry.Type().IsRegular() {
			return nil
		}
		name, err := filepath.Rel(path, entryPath)
		if err != nil {
			return err
		}
		name = filepath.ToSlash(name)
		entries++
		if entries >= maxEntries {
			return fmt.Errorf("package has too many entries")
		}
		if entry.IsDir() {
			if !oneOf(name, "cells", "assets", "reminder-links") {
				return fmt.Errorf("invalid package directory %q", name)
			}
			return nil
		}
		if !entry.Type().IsRegular() || !validRecordPath(name) {
			return fmt.Errorf("invalid package entry %q", name)
		}
		f, err := os.Open(entryPath)
		if err != nil {
			return err
		}
		defer f.Close()
		data, err := readLimited(f, min(total, recordLimit(name)))
		if err == nil {
			files[name] = data
			total -= len(data)
		}
		return err
	})
	return files, err
}

func validRecordPath(name string) bool {
	directory, file, _ := strings.Cut(name, "/")
	switch directory {
	case "cells", "reminder-links":
		id, ok := strings.CutSuffix(file, ".yaml")
		return ok && validIDs(id)
	case "assets":
		return assetPattern.MatchString(file)
	default:
		return name == "project.yaml"
	}
}

func recordLimit(name string) int {
	if strings.HasSuffix(name, ".yaml") && !strings.HasPrefix(name, "assets/") {
		return maxRecord
	}
	return maxPackage
}

func readArchive(path string) (map[string][]byte, error) {
	f, err := os.Open(path)
	if err != nil {
		return nil, err
	}
	defer f.Close()
	info, err := f.Stat()
	if err != nil {
		return nil, err
	}
	if !info.Mode().IsRegular() || info.Size() > maxPackage {
		return nil, fmt.Errorf("invalid archive or size limit exceeded")
	}
	archive, err := zip.NewReader(f, info.Size())
	if err != nil {
		return nil, err
	}
	if len(archive.File) > maxEntries {
		return nil, fmt.Errorf("archive has too many entries")
	}
	files := make(map[string][]byte, len(archive.File))
	seen := make(map[string]bool)
	total := uint64(0)
	shared := strings.EqualFold(filepath.Ext(path), ".mandalaprj")
	for _, entry := range archive.File {
		name := strings.TrimSuffix(entry.Name, "/")
		key := strings.ToLower(name)
		if !validArchivePath(name) || seen[key] || entry.UncompressedSize64 > uint64(maxPackage)-total {
			return nil, fmt.Errorf("unsafe or oversized archive entry %q", entry.Name)
		}
		seen[key] = true
		if entry.FileInfo().IsDir() {
			files[name+"/"] = nil
			continue
		}
		if !entry.Mode().IsRegular() {
			return nil, fmt.Errorf("invalid archive entry %q", entry.Name)
		}
		if shared {
			_, relative, _ := strings.Cut(name, "/")
			if !validRecordPath(relative) || entry.UncompressedSize64 > uint64(recordLimit(relative)) {
				return nil, fmt.Errorf("invalid package entry %q", entry.Name)
			}
		}
		if !shared && (strings.HasSuffix(name, "/.DS_Store") || name == ".DS_Store") {
			files[name] = []byte{}
			continue
		}
		r, err := entry.Open()
		if err != nil {
			return nil, err
		}
		data, err := readLimited(r, int(entry.UncompressedSize64))
		closeErr := r.Close()
		if err != nil || closeErr != nil || uint64(len(data)) != entry.UncompressedSize64 {
			return nil, fmt.Errorf("could not read archive entry %q", name)
		}
		if data == nil {
			data = []byte{}
		}
		files[name] = data
		total += entry.UncompressedSize64
	}
	return files, nil
}

func validArchivePath(name string) bool {
	if strings.ContainsAny(name, "\\:\x00") {
		return false
	}
	for _, part := range strings.Split(name, "/") {
		if oneOf(part, "", ".", "..") {
			return false
		}
	}
	return true
}

func decodePackage(files map[string][]byte) (*project, error) {
	p := &project{Cells: make(map[string]cell), Assets: make(map[string]asset), ReminderLinks: make(map[string]reminderLink)}
	if err := decodeYAML(files["project.yaml"], &p.Manifest); err != nil {
		return nil, fmt.Errorf("project.yaml: %w", err)
	}
	if p.Manifest.Version != 1 && p.Manifest.Version != 2 {
		return nil, fmt.Errorf("unsupported schema version %d", p.Manifest.Version)
	}
	for name, data := range files {
		folder, filename, _ := strings.Cut(name, "/")
		id := strings.TrimSuffix(filename, ".yaml")
		switch folder {
		case "cells":
			var value cell
			if p.Manifest.Version == 1 {
				var old struct {
					Cell  cell   `yaml:",inline"`
					Title string `yaml:"title"`
				}
				if err := decodeYAML(data, &old); err != nil {
					return nil, fmt.Errorf("%s: %w", name, err)
				}
				value = old.Cell
				if value.Body != nil && old.Title != "" && firstLine(*value.Body) != old.Title {
					body := old.Title
					if *value.Body != "" {
						body += "\n\n" + *value.Body
					}
					value.Body = &body
				}
			} else if err := decodeYAML(data, &value); err != nil {
				return nil, fmt.Errorf("%s: %w", name, err)
			}
			p.Cells[id] = value
		case "assets":
			p.Assets[filename] = data
		case "reminder-links":
			var value reminderLink
			if err := decodeYAML(data, &value); err != nil {
				return nil, fmt.Errorf("%s: %w", name, err)
			}
			p.ReminderLinks[id] = value
		}
	}
	p.Manifest.Version = 2
	return p, p.validate()
}

func firstLine(body string) string {
	for _, line := range strings.FieldsFunc(body, func(r rune) bool {
		return strings.ContainsRune("\r\n\v\f\u0085\u2028\u2029", r)
	}) {
		if text := strings.TrimSpace(line); text != "" {
			return text
		}
	}
	return ""
}

func packageRecords(p *project, includeReminders bool) (map[string][]byte, error) {
	if err := p.validate(); err != nil {
		return nil, err
	}
	files := make(map[string][]byte)
	encode := func(name string, record any) error {
		data, err := encodeYAML(record)
		if err == nil {
			files[name] = data
		}
		return err
	}
	if err := encode("project.yaml", p.Manifest); err != nil {
		return nil, err
	}
	for id, c := range p.Cells {
		if err := encode("cells/"+id+".yaml", c); err != nil {
			return nil, err
		}
	}
	for name, data := range p.Assets {
		files["assets/"+name] = data
	}
	if includeReminders {
		for id, link := range p.ReminderLinks {
			if err := encode("reminder-links/"+id+".yaml", link); err != nil {
				return nil, err
			}
		}
	}
	total := 0
	for name, data := range files {
		if len(data) > recordLimit(name) || len(data) > maxPackage-total {
			return nil, fmt.Errorf("package exceeds size limits at %q", name)
		}
		total += len(data)
	}
	return files, nil
}

func writePackage(path string, p *project, replace, backup bool) error {
	kind := strings.ToLower(filepath.Ext(path))
	if !oneOf(kind, ".mprj", ".mandalaprj") || replace && kind != ".mprj" || backup && kind != ".mandalaprj" {
		return fmt.Errorf("expected a .mprj or .mandalaprj output (replace applies to .mprj, backup to .mandalaprj)")
	}
	path, err := filepath.Abs(path)
	if err != nil {
		return err
	}
	parent := filepath.Dir(path)
	unlock, err := lockDirectory(parent)
	if err != nil {
		return err
	}
	defer unlock()

	expected := p.Manifest
	if replace {
		if err := checkRevision(path, expected); err != nil {
			return err
		}
		p.Manifest.Revision, err = uniqueID(func(id string) bool { return id == expected.Revision })
		if err != nil {
			return err
		}
	}
	files, err := packageRecords(p, kind == ".mprj" || backup)
	if err != nil {
		return err
	}

	staging, err := os.MkdirTemp(parent, ".mandala-write-")
	if err != nil {
		return err
	}
	keepStaging := false
	defer func() {
		if !keepStaging {
			_ = os.RemoveAll(staging)
		}
	}()
	temp := filepath.Join(staging, filepath.Base(path))
	if kind == ".mprj" {
		err = materializeProject(temp, files)
	} else {
		err = writeArchive(temp, files)
	}
	if err != nil {
		return err
	}
	if !replace {
		return installPackage(temp, path, false)
	}
	if err := checkRevision(path, expected); err != nil {
		return err
	}
	if err := installPackage(temp, path, true); err != nil {
		return err
	}
	if err := checkRevision(temp, expected); err != nil {
		keepStaging = true
		return fmt.Errorf("a concurrent update was detected during replacement; the displaced package is preserved at %s: %w", temp, err)
	}
	return nil
}

func checkRevision(path string, expected manifest) error {
	info, err := os.Lstat(path)
	if err != nil {
		return err
	}
	if !info.IsDir() {
		return fmt.Errorf("expected a .mprj directory")
	}
	name := filepath.Join(path, "project.yaml")
	info, err = os.Lstat(name)
	if err != nil {
		return err
	}
	if !info.Mode().IsRegular() {
		return fmt.Errorf("invalid project manifest")
	}
	file, err := os.Open(name)
	if err != nil {
		return err
	}
	defer file.Close()
	data, err := readLimited(file, maxRecord)
	if err != nil {
		return err
	}
	var current manifest
	if err := decodeYAML(data, &current); err != nil {
		return err
	}
	if current.ID != expected.ID || current.Revision != expected.Revision {
		return fmt.Errorf("project ID or revision changed; read the current package and retry")
	}
	return nil
}

func materializeProject(path string, files map[string][]byte) error {
	for name, data := range files {
		target := filepath.Join(path, filepath.FromSlash(name))
		if err := os.MkdirAll(filepath.Dir(target), 0700); err != nil {
			return err
		}
		if err := os.WriteFile(target, data, 0600); err != nil {
			return err
		}
	}
	return nil
}

func writeArchive(destination string, files map[string][]byte) error {
	file, err := os.OpenFile(destination, os.O_CREATE|os.O_WRONLY|os.O_EXCL, 0600)
	if err != nil {
		return err
	}
	root := strings.TrimSuffix(filepath.Base(destination), filepath.Ext(destination)) + ".mprj"
	if !validArchivePath(root) || strings.Contains(root, "/") {
		_ = file.Close()
		return fmt.Errorf("invalid archive name")
	}
	writer := zip.NewWriter(file)
	names := make([]string, 0, len(files))
	for name := range files {
		names = append(names, name)
	}
	sort.Strings(names)
	for _, name := range names {
		var entry io.Writer
		entry, err = writer.Create(root + "/" + name)
		if err != nil {
			break
		}
		if _, err = entry.Write(files[name]); err != nil {
			break
		}
	}
	if err := errors.Join(err, writer.Close(), file.Close()); err != nil {
		return err
	}
	info, err := os.Stat(destination)
	if err == nil && info.Size() > maxPackage {
		err = fmt.Errorf("archive exceeds the supported size limit")
	}
	return err
}

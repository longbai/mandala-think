//go:build darwin || linux

package main

import (
	"bytes"
	"io"
	"os"
	"path/filepath"
	"strings"
	"sync"
	"testing"
)

func TestLocateProjectByName(t *testing.T) {
	home := t.TempDir()
	t.Setenv("HOME", home)
	folder := filepath.Join(home, "Library", "Mobile Documents", "iCloud~org~mandalathink~app", "Documents")
	if err := os.MkdirAll(folder, 0700); err != nil {
		t.Fatal(err)
	}
	first := filepath.Join(folder, "Trip Planning.mprj")
	if err := runDocument("create", []string{"--output", first, "--title", "旅行计划"}, nil, io.Discard); err != nil {
		t.Fatal(err)
	}
	for _, name := range []string{"旅行计划", "trip planning", "Trip Planning.mprj"} {
		var output bytes.Buffer
		err := runDocument("locate", []string{"--name", name}, nil, &output)
		if err != nil || strings.TrimSuffix(output.String(), "\n") != first {
			t.Fatalf("locate %q: %q, %v", name, output.String(), err)
		}
	}
	second := filepath.Join(folder, "Trip Planning 2.mprj")
	if err := runDocument("create", []string{"--output", second, "--title", "旅行计划"}, nil, io.Discard); err != nil {
		t.Fatal(err)
	}
	if err := runDocument("locate", []string{"--name", "旅行计划"}, nil, io.Discard); err == nil || !strings.Contains(err.Error(), "ambiguous") {
		t.Fatalf("expected two matches, got %v", err)
	}
	if err := runDocument("locate", []string{"--name", "Missing"}, nil, io.Discard); err == nil || !strings.Contains(err.Error(), "not found") {
		t.Fatalf("expected no matches, got %v", err)
	}
	var snapshot bytes.Buffer
	if err := runDocument("export", []string{"--name", "Trip Planning 2.mprj", "--output", "-"}, nil, &snapshot); err != nil {
		t.Fatal(err)
	}
	if err := runDocument("apply", []string{"--name", "Trip Planning 2.mprj", "--input", "-"}, &snapshot, io.Discard); err != nil {
		t.Fatal(err)
	}
}

func TestYAMLDocumentCommands(t *testing.T) {
	folder := t.TempDir()
	fixture := "../MandalaCore/Tests/MandalaCoreTests/Fixtures/sample.mandala"
	document := filepath.Join(folder, "Sample.mprj")
	if err := runDocument("import", []string{"--input", fixture, "--output", document}, nil, io.Discard); err != nil {
		t.Fatal(err)
	}

	var output bytes.Buffer
	if err := runDocument("export", []string{"--project", document, "--output", "-"}, nil, &output); err != nil {
		t.Fatal(err)
	}
	base := append([]byte(nil), output.Bytes()...)
	var p project
	if err := decodeYAML(base, &p); err != nil || len(p.Cells) != 3 || len(p.Assets) != 1 {
		t.Fatalf("invalid snapshot: %v", err)
	}
	stale := p.Manifest.Revision
	body := " 引号 \"\r\n\t反斜杠 \\n\u0085\u2028e\u0301\n"
	cell := p.Cells[p.Manifest.Root]
	cell.Body = &body
	p.Cells[p.Manifest.Root] = cell
	edited, err := encodeYAML(&p)
	if err != nil {
		t.Fatal(err)
	}
	update := []string{"--project", document, "--input", "-"}
	if err := runDocument("apply", update, bytes.NewReader(edited), io.Discard); err != nil {
		t.Fatal(err)
	}
	if err := runDocument("apply", update, bytes.NewReader(base), io.Discard); err == nil {
		t.Fatal("stale revision was accepted")
	}
	updated, err := readPackage(document)
	if err != nil || updated.Manifest.Revision == stale || *updated.Cells[p.Manifest.Root].Body != body {
		t.Fatalf("invalid save: %v", err)
	}
	for name, data := range updated.Assets {
		if !bytes.Equal(data, p.Assets[name]) {
			t.Fatalf("asset %s changed", name)
		}
	}
	archive := filepath.Join(folder, "Sample.mandalaprj")
	if err := runDocument("export", []string{"--project", document, "--output", archive, "--backup"}, nil, io.Discard); err != nil {
		t.Fatal(err)
	}
	restored := filepath.Join(folder, "Restored.mprj")
	if err := runDocument("import", []string{"--input", archive, "--output", restored, "--restore"}, nil, io.Discard); err != nil {
		t.Fatal(err)
	}
	copy, err := readPackage(restored)
	if err != nil || copy.Manifest.ID != updated.Manifest.ID {
		t.Fatalf("backup restoration changed the project identity: %v", err)
	}
	if err := runDocument("validate", []string{restored}, nil, io.Discard); err == nil || !strings.Contains(err.Error(), "named flags") {
		t.Fatalf("expected positional arguments to be rejected, got %v", err)
	}
}

func TestRejectsAmbiguousYAML(t *testing.T) {
	for _, input := range []string{
		"body: before\nbody: after", "body: &a text", "body: !!str text",
		"body: 123", "body: text\nunknown: field", "body: first\n---\nbody: second",
	} {
		var c cell
		if err := decodeYAML([]byte(input), &c); err == nil {
			t.Errorf("accepted invalid YAML: %q", input)
		}
	}
}

func TestConcurrentReplacementKeepsOnlyOneRevision(t *testing.T) {
	target := filepath.Join(t.TempDir(), "Concurrent.mprj")
	if err := runDocument("create", []string{"--output", target, "--title", "Concurrent"}, nil, io.Discard); err != nil {
		t.Fatal(err)
	}
	var data bytes.Buffer
	if err := runDocument("export", []string{"--project", target, "--output", "-"}, nil, &data); err != nil {
		t.Fatal(err)
	}
	const count = 2
	var writes sync.WaitGroup
	results := make(chan error, count)
	for i := 0; i < count; i++ {
		writes.Add(1)
		go func() {
			defer writes.Done()
			results <- runDocument("apply", []string{"--project", target, "--input", "-"}, bytes.NewReader(data.Bytes()), io.Discard)
		}()
	}
	writes.Wait()
	close(results)
	success := 0
	for err := range results {
		if err == nil {
			success++
		} else if !strings.Contains(err.Error(), "revision changed") {
			t.Fatal(err)
		}
	}
	if success != 1 {
		t.Fatalf("expected one replacement, got %d", success)
	}
}

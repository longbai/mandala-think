//go:build darwin || linux

package main

import (
	"bytes"
	"io"
	"path/filepath"
	"strings"
	"sync"
	"testing"
)

func TestYAMLDocumentCommands(t *testing.T) {
	folder := t.TempDir()
	fixture := "../MandalaCore/Tests/MandalaCoreTests/Fixtures/sample.mandala"
	document := filepath.Join(folder, "Sample.mprj")
	if err := runDocument("convert", []string{fixture, document}, nil, io.Discard); err != nil {
		t.Fatal(err)
	}

	var output bytes.Buffer
	if err := runDocument("read", []string{document}, nil, &output); err != nil {
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
	update := []string{"--replace", document}
	if err := runDocument("write", update, bytes.NewReader(edited), io.Discard); err != nil {
		t.Fatal(err)
	}
	if err := runDocument("write", update, bytes.NewReader(base), io.Discard); err == nil {
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
	if err := runDocument("new", []string{target, "Concurrent"}, nil, io.Discard); err != nil {
		t.Fatal(err)
	}
	var data bytes.Buffer
	if err := runDocument("read", []string{target}, nil, &data); err != nil {
		t.Fatal(err)
	}
	const count = 2
	var writes sync.WaitGroup
	results := make(chan error, count)
	for i := 0; i < count; i++ {
		writes.Add(1)
		go func() {
			defer writes.Done()
			results <- runDocument("write", []string{"--replace", target}, bytes.NewReader(data.Bytes()), io.Discard)
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

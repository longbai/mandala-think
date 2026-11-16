package main

import (
	"encoding/xml"
	"fmt"
	"path/filepath"
	"regexp"
	"sort"
	"strconv"
	"strings"
	"unicode/utf8"
)

var legacyExtension = regexp.MustCompile(`^[a-z0-9]{1,16}$`)

func legacyNumber(name string) (int, bool) {
	number, _ := strings.CutSuffix(name, ".cell")
	id, err := strconv.Atoi(number)
	return id, err == nil && id >= 0 && name == strconv.Itoa(id)+".cell"
}

func importLegacy(filename string, files map[string][]byte) (*project, error) {
	nodes := make(map[string]map[string][]byte)
	for name, data := range files {
		parts := strings.Split(strings.TrimSuffix(name, "/"), "/")
		if _, ok := legacyNumber(parts[0]); !ok {
			continue
		}
		index := 0
		for {
			route := strings.Join(parts[:index+1], "/")
			if nodes[route] == nil {
				nodes[route] = make(map[string][]byte)
			}
			if index+2 >= len(parts) || parts[index+1] != "Children" {
				rest := parts[index+1:]
				if data != nil && len(rest) == 2 && rest[0] == "Contents" && strings.HasPrefix(rest[1], "Content.") {
					nodes[route][rest[1]] = data
				}
				break
			}
			if _, ok := legacyNumber(parts[index+2]); !ok {
				break
			}
			index += 2
			if index > 256 || len(nodes) > 20000 {
				return nil, fmt.Errorf("legacy project exceeds layout limits")
			}
		}
	}

	var root string
	for route := range nodes {
		if !strings.Contains(route, "/") {
			if root != "" {
				return nil, fmt.Errorf("expected one legacy root cell")
			}
			root = route
		}
	}
	if root == "" {
		return nil, fmt.Errorf("missing legacy root cell")
	}
	title := strings.TrimSuffix(filename, filepath.Ext(filename))
	p, err := newProject(title, "")
	if err != nil {
		return nil, err
	}
	rootNumber, _ := legacyNumber(root)
	p.Manifest.LegacyRoot = &rootNumber
	p.Assets = make(map[string]asset)
	ids := map[string]string{root: p.Manifest.Root}
	used := map[string]bool{p.Manifest.Root: true}
	for route := range nodes {
		if route != root {
			id, err := uniqueID(func(id string) bool { return used[id] })
			if err != nil {
				return nil, err
			}
			ids[route], used[id] = id, true
		}
	}
	for route, contents := range nodes {
		if !utf8.Valid(contents["Content.txt"]) {
			return nil, fmt.Errorf("invalid UTF-8 in %s", route)
		}
		body := string(contents["Content.txt"])
		value := cell{Body: &body}
		names := make([]string, 0, len(contents))
		for name := range contents {
			names = append(names, name)
		}
		sort.Strings(names)
		for _, name := range names {
			ext := strings.ToLower(strings.TrimPrefix(filepath.Ext(name), "."))
			if name == "Content.txt" || !legacyExtension.MatchString(ext) {
				continue
			}
			kind := "file"
			switch ext {
			case "jpg", "jpeg", "png", "gif", "webp", "heic":
				kind = "image"
			case "mp4", "mov", "m4v":
				kind = "video"
			case "mp3", "wav", "aac", "m4a":
				kind = "audio"
			}
			path, err := p.storeLegacyAsset(ext, contents[name])
			if err != nil {
				return nil, err
			}
			value.Resources = append(value.Resources, resource{Kind: kind, Path: path, OriginalFilename: name})
		}
		p.Cells[ids[route]] = value
	}
	for route, id := range ids {
		if route == root {
			continue
		}
		separator := strings.LastIndex(route, "/Children/")
		number, _ := legacyNumber(route[separator+len("/Children/"):])
		parentID := ids[route[:separator]]
		parent := p.Cells[parentID]
		if number < len(slots) && slots[number] != "" {
			if parent.Children == nil {
				parent.Children = make(map[string]string)
			}
			parent.Children[slots[number]] = id
		} else {
			if parent.LegacyChildren == nil {
				parent.LegacyChildren = make(map[string]string)
			}
			parent.LegacyChildren[strconv.Itoa(number)] = id
		}
		p.Cells[parentID] = parent
	}
	preview := legacyPreview(files)
	if data := files[preview]; data != nil {
		ext := strings.ToLower(strings.TrimPrefix(filepath.Ext(preview), "."))
		if oneOf(ext, "jpg", "jpeg", "png", "gif", "webp", "heic") {
			path, err := p.storeLegacyAsset(ext, data)
			if err != nil {
				return nil, err
			}
			p.Manifest.LegacyPreview = path
			root := p.Cells[p.Manifest.Root]
			hasImage := false
			for _, item := range root.Resources {
				hasImage = hasImage || item.Kind == "image"
			}
			if !hasImage {
				root.Resources = append([]resource{{Kind: "image", Path: path, OriginalFilename: filepath.Base(preview)}}, root.Resources...)
				p.Cells[p.Manifest.Root] = root
			}
		}
	}
	return p, p.validate()
}

func uniqueID(taken func(string) bool) (string, error) {
	for {
		id, err := shortID()
		if err != nil || !taken(id) {
			return id, err
		}
	}
}

func (p *project) storeLegacyAsset(ext string, data []byte) (string, error) {
	id, err := uniqueID(func(id string) bool {
		_, exists := p.Assets[id+"."+ext]
		return exists
	})
	if err != nil {
		return "", err
	}
	name := id + "." + ext
	p.Assets[name] = data
	return "assets/" + name, nil
}

func legacyPreview(files map[string][]byte) string {
	var plist struct {
		Dict struct {
			Entries []struct {
				Name  xml.Name
				Value string `xml:",chardata"`
			} `xml:",any"`
		} `xml:"dict"`
	}
	if xml.Unmarshal(files["Representing/RepresentingInfo.plist"], &plist) == nil {
		for index, entry := range plist.Dict.Entries {
			if entry.Name.Local == "key" && entry.Value == "representingEntry" && index+1 < len(plist.Dict.Entries) {
				value := plist.Dict.Entries[index+1]
				if value.Name.Local == "string" && files[value.Value] != nil && strings.HasPrefix(value.Value, "Representing/") {
					return value.Value
				}
			}
		}
	}
	return "Representing/Representing.png"
}

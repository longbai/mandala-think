package main

import (
	"bytes"
	"crypto/rand"
	"encoding/base64"
	"fmt"
	"io"
	"math/big"
	"net/url"
	"reflect"
	"regexp"
	"strconv"
	"strings"
	"time"
	_ "time/tzdata"

	"go.yaml.in/yaml/v3"
)

const (
	idAlphabet = "0123456789abcdefghijklmnopqrstuvwxyz-_~"
	maxPackage = 256 << 20
	maxRecord  = 16 << 20
	maxEntries = 30000
)

var (
	idPattern      = regexp.MustCompile(`^[0-9a-z_~-]{13}$`)
	assetPattern   = regexp.MustCompile(`^[0-9a-z_~-]{13}\.[a-z0-9]{1,16}$`)
	integerPattern = regexp.MustCompile(`^-?(0|[1-9][0-9]*)$`)
	slots          = []string{"top_left", "top", "top_right", "left", "", "right", "bottom_left", "bottom", "bottom_right"}
)

type manifest struct {
	Version       int     `yaml:"schema_version"`
	ID            string  `yaml:"project_id"`
	Title         *string `yaml:"title"`
	Root          string  `yaml:"root_cell_id"`
	Revision      string  `yaml:"revision"`
	LegacyRoot    *int    `yaml:"legacy_root_id,omitempty"`
	LegacyPreview string  `yaml:"legacy_preview_path,omitempty"`
	Template      string  `yaml:"template,omitempty"`
}

type cell struct {
	Body           *string           `yaml:"body"`
	Color          string            `yaml:"color,omitempty"`
	Children       map[string]string `yaml:"children,omitempty"`
	LegacyChildren map[string]string `yaml:"legacy_children,omitempty"`
	Resources      []resource        `yaml:"resources,omitempty"`
	Actions        []action          `yaml:"actions,omitempty"`
}

type resource struct {
	Kind             string `yaml:"kind"`
	URL              string `yaml:"url,omitempty"`
	Path             string `yaml:"path,omitempty"`
	Title            string `yaml:"title,omitempty"`
	Caption          string `yaml:"caption,omitempty"`
	OriginalFilename string `yaml:"original_filename,omitempty"`
}

type action struct {
	ID    string `yaml:"id"`
	Title string `yaml:"title"`
	Notes string `yaml:"notes,omitempty"`
	Due   *due   `yaml:"due,omitempty"`
}

type due struct {
	Date     string `yaml:"date"`
	Time     string `yaml:"time,omitempty"`
	TimeZone string `yaml:"time_zone,omitempty"`
}

type reminderLink struct {
	ProjectID      string `yaml:"project_id"`
	CellID         string `yaml:"cell_id"`
	State          string `yaml:"state"`
	OperationID    string `yaml:"operation_id"`
	SystemExternal string `yaml:"system_external_id,omitempty"`
	SystemItem     string `yaml:"system_item_id,omitempty"`
	ListHint       string `yaml:"list_hint,omitempty"`
}

type asset []byte

func (a asset) MarshalYAML() (any, error) {
	return base64.StdEncoding.EncodeToString(a), nil
}

func (a *asset) UnmarshalYAML(node *yaml.Node) error {
	if node.Kind != yaml.ScalarNode || node.ShortTag() != "!!str" {
		return fmt.Errorf("an asset must be a base64 string")
	}
	data, err := base64.StdEncoding.DecodeString(node.Value)
	if err != nil {
		return err
	}
	*a = data
	return nil
}

type project struct {
	Manifest      manifest                `yaml:"manifest"`
	Cells         map[string]cell         `yaml:"cells"`
	Assets        map[string]asset        `yaml:"assets,omitempty"`
	ReminderLinks map[string]reminderLink `yaml:"reminder_links,omitempty"`
}

func shortID() (string, error) {
	id := make([]byte, 13)
	limit := big.NewInt(int64(len(idAlphabet)))
	for index := range id {
		value, err := rand.Int(rand.Reader, limit)
		if err != nil {
			return "", err
		}
		id[index] = idAlphabet[value.Int64()]
	}
	return string(id), nil
}

func newProject(title, center string) (*project, error) {
	root, err := shortID()
	if err != nil {
		return nil, err
	}
	id, err := shortID()
	if err != nil {
		return nil, err
	}
	revision, err := shortID()
	if err != nil {
		return nil, err
	}
	return &project{
		Manifest: manifest{Version: 2, ID: id, Root: root, Revision: revision, Title: &title},
		Cells:    map[string]cell{root: {Body: &center}},
	}, nil
}

func (p *project) assetExists(path string) bool {
	name, ok := strings.CutPrefix(path, "assets/")
	_, exists := p.Assets[name]
	return ok && assetPattern.MatchString(name) && exists
}

func (p *project) validate() error {
	m := p.Manifest
	if m.Version != 2 || m.Title == nil || !validIDs(m.ID, m.Revision, m.Root) ||
		(m.LegacyRoot != nil && *m.LegacyRoot < 0) || !oneOf(m.Template, "", "five_w", "time") {
		return fmt.Errorf("invalid project manifest")
	}
	if len(p.Cells) > 20000 || len(p.Cells)+len(p.Assets)+len(p.ReminderLinks)+5 > maxEntries {
		return fmt.Errorf("project has too many entries")
	}
	for name := range p.Assets {
		if !assetPattern.MatchString(name) {
			return fmt.Errorf("invalid asset filename %q", name)
		}
	}
	if m.LegacyPreview != "" && !p.assetExists(m.LegacyPreview) {
		return fmt.Errorf("missing cover asset %q", m.LegacyPreview)
	}
	visited, actions := make(map[string]bool), make(map[string]bool)
	if err := p.visitCell(m.Root, 0, visited, actions); err != nil {
		return err
	}
	if len(visited) != len(p.Cells) {
		return fmt.Errorf("the project contains cells outside the root tree")
	}
	operations := make(map[string]bool)
	for id, link := range p.ReminderLinks {
		if !validIDs(id, link.CellID, link.OperationID) || link.ProjectID != m.ID ||
			!oneOf(link.State, "pending", "created", "uncertain") || operations[link.OperationID] {
			return fmt.Errorf("invalid reminder record %q", id)
		}
		operations[link.OperationID] = true
	}
	return nil
}

func (p *project) visitCell(id string, depth int, visited, actions map[string]bool) error {
	c, exists := p.Cells[id]
	if depth > 128 || !exists || !validIDs(id) || c.Body == nil || visited[id] ||
		!oneOf(c.Color, "", "red", "orange", "yellow", "green", "blue", "purple", "gray") {
		return fmt.Errorf("invalid, missing, or repeated cell %q", id)
	}
	visited[id] = true
	for slot, child := range c.Children {
		if slot == "" || !oneOf(slot, slots...) {
			return fmt.Errorf("invalid slot %q in cell %q", slot, id)
		}
		if err := p.visitCell(child, depth+1, visited, actions); err != nil {
			return err
		}
	}
	for key, child := range c.LegacyChildren {
		number, err := strconv.Atoi(key)
		if err != nil || number < 0 || key != strconv.Itoa(number) || (number < len(slots) && slots[number] != "") {
			return fmt.Errorf("invalid legacy slot %q in cell %q", key, id)
		}
		if err := p.visitCell(child, depth+1, visited, actions); err != nil {
			return err
		}
	}
	for _, item := range c.Resources {
		if !oneOf(item.Kind, "link", "image", "video", "audio", "file") ||
			!(item.URL == "" && item.Kind != "link" && p.assetExists(item.Path) || item.Path == "" && isWebURL(item.URL)) {
			return fmt.Errorf("invalid resource in cell %q", id)
		}
	}
	for _, item := range c.Actions {
		if !validIDs(item.ID) || actions[item.ID] || strings.TrimSpace(item.Title) == "" ||
			strings.ContainsAny(item.Title, "\r\n\v\f\u0085\u2028\u2029") || item.Due != nil && !item.Due.valid() {
			return fmt.Errorf("invalid action %q in cell %q", item.ID, id)
		}
		actions[item.ID] = true
	}
	return nil
}

func (d due) valid() bool {
	date, err := time.Parse("2006-01-02", d.Date)
	if err != nil || date.Year() < 1 || date.Format("2006-01-02") != d.Date {
		return false
	}
	if d.Time == "" {
		return d.TimeZone == ""
	}
	clock, err := time.Parse("15:04", d.Time)
	if err != nil || clock.Format("15:04") != d.Time || d.TimeZone == "" || d.TimeZone == "Local" {
		return false
	}
	location, err := time.LoadLocation(d.TimeZone)
	if err != nil {
		return false
	}
	local := time.Date(date.Year(), date.Month(), date.Day(), clock.Hour(), clock.Minute(), 0, 0, location)
	layout := "2006-01-02 15:04"
	if local.Format(layout) != d.Date+" "+d.Time {
		return false
	}
	_, offset := local.Zone()
	for _, day := range []int{-1, 1} {
		_, other := local.AddDate(0, 0, day).Zone()
		if other != offset && local.Add(time.Duration(offset-other)*time.Second).Format(layout) == local.Format(layout) {
			return false
		}
	}
	return true
}

func validIDs(ids ...string) bool {
	for _, id := range ids {
		if !idPattern.MatchString(id) {
			return false
		}
	}
	return true
}

func oneOf(value string, options ...string) bool {
	for _, option := range options {
		if value == option {
			return true
		}
	}
	return false
}

func isWebURL(value string) bool {
	parsed, err := url.Parse(value)
	return err == nil && parsed.Hostname() != "" && oneOf(strings.ToLower(parsed.Scheme), "http", "https")
}

func decodeYAML(data []byte, value any) error {
	d := yaml.NewDecoder(bytes.NewReader(data))
	var node yaml.Node
	if err := d.Decode(&node); err != nil {
		return err
	}
	if len(node.Content) != 1 || node.Content[0].Kind != yaml.MappingNode {
		return fmt.Errorf("expected a YAML mapping")
	}
	if err := checkYAML(node.Content[0], reflect.TypeOf(value), 0); err != nil {
		return err
	}
	if err := d.Decode(&yaml.Node{}); err != io.EOF {
		return fmt.Errorf("expected exactly one YAML document")
	}
	d = yaml.NewDecoder(bytes.NewReader(data))
	d.KnownFields(true)
	return d.Decode(value)
}

func checkYAML(node *yaml.Node, target reflect.Type, depth int) error {
	if depth > 16 || node.Anchor != "" || node.Style&yaml.TaggedStyle != 0 {
		return fmt.Errorf("unsupported YAML tag, anchor, or depth")
	}
	if target != nil && target.Kind() == reflect.Pointer {
		target = target.Elem()
	}
	switch node.Kind {
	case yaml.MappingNode:
		keys := make(map[string]bool)
		for index := 0; index < len(node.Content); index += 2 {
			key := node.Content[index]
			if key.ShortTag() != "!!str" || key.Anchor != "" || key.Style&yaml.TaggedStyle != 0 ||
				key.Value == "<<" || keys[key.Value] {
				return fmt.Errorf("invalid or duplicate YAML key %q", key.Value)
			}
			keys[key.Value] = true
			if err := checkYAML(node.Content[index+1], yamlFieldType(target, key.Value), depth+1); err != nil {
				return err
			}
		}
	case yaml.SequenceNode:
		var element reflect.Type
		if target != nil && target.Kind() == reflect.Slice {
			element = target.Elem()
		}
		for _, child := range node.Content {
			if err := checkYAML(child, element, depth+1); err != nil {
				return err
			}
		}
	case yaml.ScalarNode:
		tag := node.ShortTag()
		if tag != "!!str" && !(tag == "!!int" && integerPattern.MatchString(node.Value)) {
			return fmt.Errorf("unsupported YAML scalar %q", node.ShortTag())
		}
		if target != nil && (target.Kind() == reflect.String && tag != "!!str" ||
			target.Kind() == reflect.Int && tag != "!!int") {
			return fmt.Errorf("unexpected YAML type at line %d", node.Line)
		}
	default:
		return fmt.Errorf("unsupported YAML node")
	}
	return nil
}

func yamlFieldType(target reflect.Type, key string) reflect.Type {
	if target == nil {
		return nil
	}
	switch target.Kind() {
	case reflect.Map:
		return target.Elem()
	case reflect.Struct:
		for index := 0; index < target.NumField(); index++ {
			field := target.Field(index)
			name, options, _ := strings.Cut(field.Tag.Get("yaml"), ",")
			if name == key {
				return field.Type
			}
			if options == "inline" {
				if fieldType := yamlFieldType(field.Type, key); fieldType != nil {
					return fieldType
				}
			}
		}
	}
	return nil
}

func encodeYAML(value any) ([]byte, error) {
	var node yaml.Node
	if err := node.Encode(value); err != nil {
		return nil, err
	}
	quoteStrings(&node)
	var output bytes.Buffer
	encoder := yaml.NewEncoder(&output)
	encoder.SetIndent(2)
	if err := encoder.Encode(&node); err != nil {
		return nil, err
	}
	if err := encoder.Close(); err != nil {
		return nil, err
	}
	return output.Bytes(), nil
}

func quoteStrings(node *yaml.Node) {
	if node.Kind == yaml.ScalarNode && node.ShortTag() == "!!str" {
		node.Style = yaml.DoubleQuotedStyle
	}
	for _, child := range node.Content {
		quoteStrings(child)
	}
}

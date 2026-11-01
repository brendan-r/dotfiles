// Package installerui provides a standalone, data-driven installer interface.
// It knows nothing about package managers, YAML, or dotfiles paths.
package installerui

import (
	tea "charm.land/bubbletea/v2"
	"fmt"
	"time"
)

type Group struct {
	ID    string `json:"id"`
	Label string `json:"label"`
}
type Option struct {
	ID    string `json:"id"`
	Label string `json:"label"`
}
type Item struct {
	Operations []string `json:"operations,omitempty"`
	Options    []Option `json:"options,omitempty"`
	Choices    []string `json:"choices,omitempty"`
	ID         string   `json:"id"`
	Label      string   `json:"label"`
	Group      string   `json:"group"`
	Parent     string   `json:"parent,omitempty"`
	Status     string   `json:"status"`
	Note       string   `json:"note,omitempty"`
	Requires   []string `json:"requires,omitempty"`
	Selected   bool     `json:"selected"`
}
type Completion struct {
	File         string `json:"file"`
	Title        string `json:"title"`
	SuccessTitle string `json:"success_title"`
	SuccessText  string `json:"success_text"`
	Button       string `json:"button"`
}
type Request struct {
	Brand      string     `json:"brand,omitempty"`
	Completion Completion `json:"completion,omitempty"`
	Version    int        `json:"version"`
	Title      string     `json:"title"`
	Groups     []Group    `json:"groups"`
	Items      []Item     `json:"items"`
}
type Result struct {
	Choices  map[string][]string `json:"choices"`
	Action   string              `json:"action"`
	Selected []string            `json:"selected"`
}

type row struct {
	option int
	group  string
	item   int
}
type Model struct {
	request                       Request
	rows                          []row
	selected                      map[string]bool
	choices                       map[string]map[string]bool
	index                         map[string]int
	cursor, offset, height, width int
	message                       string
	colour                        bool
	Result                        Result
}

// New validates references before a terminal is opened. Parent controls visual
// nesting; requires controls dependency selection. They are deliberately distinct.
func New(req Request, colour bool) (*Model, error) {
	if req.Version != 1 {
		return nil, fmt.Errorf("unsupported interface version %d", req.Version)
	}
	m := &Model{request: req, selected: map[string]bool{}, choices: map[string]map[string]bool{}, index: map[string]int{}, height: 24, width: 80, colour: colour}
	groups := map[string]bool{}
	for _, g := range req.Groups {
		if g.ID == "" || groups[g.ID] {
			return nil, fmt.Errorf("duplicate or empty group")
		}
		groups[g.ID] = true
	}
	for i, it := range req.Items {
		if it.ID == "" {
			return nil, fmt.Errorf("empty item ID")
		}
		if _, ok := m.index[it.ID]; ok {
			return nil, fmt.Errorf("duplicate item %s", it.ID)
		}
		if !groups[it.Group] {
			return nil, fmt.Errorf("unknown group for %s", it.ID)
		}
		m.index[it.ID] = i
		m.choices[it.ID] = map[string]bool{}
		seenOptions := map[string]bool{}
		for _, o := range it.Options {
			if o.ID == "" || seenOptions[o.ID] {
				return nil, fmt.Errorf("duplicate or empty option")
			}
			seenOptions[o.ID] = true
		}

	}
	for _, it := range req.Items {
		if it.Parent != "" {
			if _, ok := m.index[it.Parent]; !ok {
				return nil, fmt.Errorf("unknown parent %s", it.Parent)
			}
		}
		for _, id := range it.Requires {
			if _, ok := m.index[id]; !ok {
				return nil, fmt.Errorf("unknown dependency %s", id)
			}
		}
		seen := map[string]bool{}
		id := it.ID
		for id != "" {
			if seen[id] {
				return nil, fmt.Errorf("parent cycle")
			}
			seen[id] = true
			id = req.Items[m.index[id]].Parent
		}
	}
	// Detect cycles independently of defaults, including disabled entries.
	visiting, visited := map[string]bool{}, map[string]bool{}
	var visit func(string) error
	visit = func(id string) error {
		if visiting[id] {
			return fmt.Errorf("dependency cycle at %s", id)
		}
		if visited[id] {
			return nil
		}
		visiting[id] = true
		for _, d := range req.Items[m.index[id]].Requires {
			if err := visit(d); err != nil {
				return err
			}
		}
		delete(visiting, id)
		visited[id] = true
		return nil
	}
	for _, it := range req.Items {
		if err := visit(it.ID); err != nil {
			return nil, err
		}
	}
	for _, g := range req.Groups {
		m.rows = append(m.rows, row{group: g.Label, item: -1})
		for i, it := range req.Items {
			if it.Group == g.ID {
				m.rows = append(m.rows, row{item: i, option: -1})
				for n := range it.Options {
					m.rows = append(m.rows, row{item: i, option: n})
				}
			}
		}
	}
	for _, it := range req.Items {
		if it.Selected && it.Status == "ready" {
			if err := m.add(it.ID); err != nil {
				return nil, err
			}
		}
	}
	// Explicit choices preserve partial bundles when returning from review.
	for _, it := range req.Items {
		if it.Choices != nil && m.selected[it.ID] {
			m.choices[it.ID] = map[string]bool{}
			for _, id := range it.Choices {
				found := false
				for _, o := range it.Options {
					if o.ID == id {
						found = true
					}
				}
				if !found {
					return nil, fmt.Errorf("unknown option %s", id)
				}
				m.choices[it.ID][id] = true
			}
			if len(it.Options) > 0 && len(it.Choices) == 0 {
				m.remove(it.ID)
			}
		}
	}
	for m.cursor < len(m.rows) && m.rows[m.cursor].item < 0 {
		m.cursor++
	}
	return m, nil
}

// Validate the entire dependency closure before changing selection. Existing
// dependencies retain their partial choices when another item requires them.
func (m *Model) add(id string) error {
	order := []string{}
	seen := map[string]bool{}
	var collect func(string) error
	collect = func(current string) error {
		if seen[current] || m.selected[current] {
			return nil
		}
		seen[current] = true
		it := m.request.Items[m.index[current]]
		if it.Status != "ready" {
			return fmt.Errorf("%s is unavailable", it.Label)
		}
		for _, dependency := range it.Requires {
			if err := collect(dependency); err != nil {
				return err
			}
		}
		order = append(order, current)
		return nil
	}
	if err := collect(id); err != nil {
		return err
	}
	for _, current := range order {
		m.selected[current] = true
		for _, option := range m.request.Items[m.index[current]].Options {
			m.choices[current][option.ID] = true
		}
	}
	return nil
}
func (m *Model) remove(id string) {
	delete(m.selected, id)
	m.choices[id] = map[string]bool{}
	for _, it := range m.request.Items {
		if m.selected[it.ID] {
			for _, d := range it.Requires {
				if d == id {
					m.remove(it.ID)
				}
			}
		}
	}
}
func (m *Model) finish(action string) tea.Cmd {
	m.Result = Result{Action: action, Selected: []string{}, Choices: map[string][]string{}}
	for _, it := range m.request.Items {
		if m.selected[it.ID] {
			m.Result.Selected = append(m.Result.Selected, it.ID)
			if len(it.Options) > 0 {
				m.Result.Choices[it.ID] = []string{}
				for _, o := range it.Options {
					if m.choices[it.ID][o.ID] {
						m.Result.Choices[it.ID] = append(m.Result.Choices[it.ID], o.ID)
					}
				}
			}
		}
	}
	return tea.Quit
}
func (m *Model) Init() tea.Cmd {
	return nil
}

type pulseMsg struct{}

func pulse() tea.Cmd {
	return tea.Tick(100*time.Millisecond, func(time.Time) tea.Msg { return pulseMsg{} })
}
func (m *Model) Update(msg tea.Msg) (tea.Model, tea.Cmd) {
	switch v := msg.(type) {
	case tea.WindowSizeMsg:
		m.width = v.Width
		m.height = v.Height
	case tea.KeyPressMsg:
		key := v.String()
		if key == "ctrl+c" {
			return m, m.finish("interrupt")
		}
		if key == "esc" || key == "q" {
			return m, m.finish("cancel")
		}
		if m.width < 30 || m.height < 10 {
			return m, nil
		}
		if len(m.rows) == 0 && key != "enter" {
			return m, nil
		}
		switch key {
		case "enter":
			return m, m.finish("install")
		case "up", "k", "down", "j", "pgup", "pgdown", "home", "end":
			direction := 1
			if key == "up" || key == "k" || key == "pgup" {
				direction = -1
			}
			steps := 1
			if key == "pgup" || key == "pgdown" {
				steps = max(1, m.height-8)
			}
			if key == "home" {
				m.cursor = 0
			}
			if key == "end" {
				m.cursor = len(m.rows) - 1
			}
			for n := 0; n < steps; n++ {
				if key != "home" && key != "end" {
					m.cursor = max(0, min(len(m.rows)-1, m.cursor+direction))
				}
				if m.cursor < len(m.rows) && m.rows[m.cursor].item < 0 {
					next := m.cursor + direction
					if next >= 0 && next < len(m.rows) {
						m.cursor = next
					}
				}
			}
		case "c":
			m.selected = map[string]bool{}
			for id := range m.choices {
				m.choices[id] = map[string]bool{}
			}
		case "space", "x":
			if m.cursor >= len(m.rows) || m.rows[m.cursor].item < 0 {
				break
			}
			it := m.request.Items[m.rows[m.cursor].item]
			m.message = ""
			if it.Status != "ready" {
				m.message = it.Note
				if m.message == "" {
					m.message = "This option is not implemented yet."
				}
				break
			}
			if option := m.rows[m.cursor].option; option >= 0 {
				if !m.selected[it.ID] {
					if err := m.add(it.ID); err != nil {
						m.message = err.Error()
						break
					}
					m.choices[it.ID] = map[string]bool{}
				}
				id := it.Options[option].ID
				if m.choices[it.ID][id] {
					delete(m.choices[it.ID], id)
				} else {
					m.choices[it.ID][id] = true
				}
				if len(m.choices[it.ID]) == 0 {
					m.remove(it.ID)
				} else {
					m.selected[it.ID] = true
				}
				break
			}
			if m.selected[it.ID] {
				m.remove(it.ID)
			} else {
				if err := m.add(it.ID); err != nil {
					m.message = err.Error()
				}
			}
		}
	}
	return m, nil
}
func (m *Model) style(s, code string) string {
	if !m.colour {
		return s
	}
	return "\x1b[" + code + "m" + s + "\x1b[0m"
}
func (m *Model) View() tea.View {
	return m.selectionView()
}

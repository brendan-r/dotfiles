package installerui

import (
	"fmt"
	"strings"

	tea "charm.land/bubbletea/v2"
	"github.com/charmbracelet/x/ansi"
)

// Shared geometry keeps borders and content within the terminal, including
// double-width characters. The secondary pane disappears on small screens.
func paneWidths(width int) (int, int) {
	if width < 96 {
		return max(10, width), 0
	}
	right := min(44, width/3)
	return width - right - 1, right
}

func paint(text, code string, colour bool) string {
	if !colour {
		return text
	}
	return "\x1b[" + code + "m" + text + "\x1b[0m"
}

func fit(text string, width int) string {
	text = ansi.Truncate(text, max(0, width), "…")
	return text + strings.Repeat(" ", max(0, width-ansi.StringWidth(text)))
}

func panel(title string, lines []string, width, height int, colour bool) []string {
	inside := max(1, width-4)
	border := func(s string) string { return paint(s, "38;5;60", colour) }
	heading := ansi.Truncate(" "+title+" ", width-2, "…")
	out := []string{border("╭") + paint(heading, "1;38;5;117", colour) + border(strings.Repeat("─", max(0, width-2-ansi.StringWidth(heading)))+"╮")}
	for i := 0; i < height; i++ {
		line := ""
		if i < len(lines) {
			line = lines[i]
		}
		out = append(out, border("│")+" "+fit(line, inside)+" "+border("│"))
	}
	return append(out, border("╰"+strings.Repeat("─", max(0, width-2))+"╯"))
}

func columns(left, right []string) string {
	if len(right) == 0 {
		return strings.Join(left, "\n")
	}
	lines := make([]string, len(left))
	for i := range left {
		lines[i] = left[i] + " " + right[i]
	}
	return strings.Join(lines, "\n")
}

func (m *Model) selectionView() tea.View {
	if m.width < 30 || m.height < 10 {
		v := tea.NewView("Resize terminal to 30×10 or larger.\nEsc: cancel")
		v.AltScreen = true
		return v
	}
	leftWidth, rightWidth := paneWidths(m.width)
	size := max(1, m.height-8)
	m.offset = max(0, min(m.offset, max(0, len(m.rows)-size)))
	if m.cursor < m.offset {
		m.offset = m.cursor
	}
	if m.cursor >= m.offset+size {
		m.offset = m.cursor - size + 1
	}
	var lines []string
	for n := m.offset; n < min(len(m.rows), m.offset+size); n++ {
		r := m.rows[n]
		if r.item < 0 {
			lines = append(lines, m.style(r.group, "1;38;5;141"))
			continue
		}
		it := m.request.Items[r.item]
		indent := "  "
		for parent := it.Parent; parent != ""; parent = m.request.Items[m.index[parent]].Parent {
			indent += "  "
		}
		marker, label := "○", it.Label
		if m.selected[it.ID] {
			marker = m.style("●", "38;5;84")
		}
		if r.option >= 0 {
			o := it.Options[r.option]
			label = o.Label
			indent += "  "
			marker = "○"
			if m.choices[it.ID][o.ID] {
				marker = m.style("●", "38;5;84")
			}
		} else if len(it.Options) > 0 && len(m.choices[it.ID]) > 0 && len(m.choices[it.ID]) < len(it.Options) {
			marker = m.style("◐", "33")
		}
		if it.Status != "ready" {
			marker = "·"
			status := "needs review"
			if it.Status == "planned" {
				status = "not implemented"
			}
			label = m.style(label+" · "+status, "90")
		}
		cursor := " "
		if n == m.cursor {
			cursor = m.style("›", "1;38;5;117")
			label = m.style(label, "1")
		}
		lines = append(lines, cursor+indent+marker+" "+label)
	}
	var note string
	var details []string
	if m.cursor < len(m.rows) && m.rows[m.cursor].item >= 0 {
		it := m.request.Items[m.rows[m.cursor].item]
		note = it.Note
		details = append(details, m.style(it.Label, "1;38;5;84"), "")
		if note != "" {
			details = append(details, strings.Split(ansi.Wrap(note, max(1, rightWidth-4), ""), "\n")...)
			details = append(details, "")
		}
		for _, op := range it.Operations {
			details = append(details, strings.Split(ansi.Wrap("• "+op, max(1, rightWidth-4), ""), "\n")...)
		}
		if len(it.Requires) > 0 {
			details = append(details, "", m.style("Also selects", "1;38;5;141"))
			for _, id := range it.Requires {
				details = append(details, m.request.Items[m.index[id]].Label)
			}
		}
		if it.Status != "ready" {
			details = append(details, "", "Not available for installation yet.")
		}
	}
	if m.message != "" {
		note = m.message
	}
	var right []string
	if rightWidth > 0 {
		right = panel("What this does", details, rightWidth, size, m.colour)
	}
	title := m.style("  ✦  "+m.request.Title, "1;38;5;117")
	if m.request.Brand != "" {
		title = brandHeader(m.request.Brand, m.width, m.colour)
	}
	subtitle := m.style("  Recommended options are pre-selected. Enter starts installation.", "90")
	footer := fmt.Sprintf("  %d selected  ·  Space: toggle · c: clear · Enter: install · Esc: cancel", len(m.selected))
	text := fit(title, m.width) + "\n" + fit(subtitle, m.width) + "\n\n" + columns(panel("Installation", lines, leftWidth, size, m.colour), right) + "\n" + fit("  "+note, m.width) + "\n" + fit(footer, m.width)
	v := tea.NewView(text)
	v.AltScreen = true
	return v
}

// Keep the brand compact so a decorative heading never crowds out choices.
func brandHeader(brand string, width int, colour bool) string {
	text := paint("  ✧  ", "38;5;213", colour) + paint(brand, "1;38;5;117", colour) + paint("  ✦", "38;5;213", colour)
	return text + paint("  "+strings.Repeat("━", max(0, width-ansi.StringWidth(text)-4)), "38;5;60", colour)
}

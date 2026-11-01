package installerui

import (
	"fmt"
	"io"
	"os"
	"strings"
	"unicode"

	tea "charm.land/bubbletea/v2"
	"github.com/charmbracelet/x/ansi"
)

// Preview the user's existing Org document without modifying its formatting or
// executing anything in it. Bound reads and strip terminal control sequences.
func (m *Dashboard) loadCompletion() {
	defer func() {
		details := m.completionDetails()
		if details != "" {
			m.todo = details + "\n\n* Remaining manual setup\nThese are normal follow-up tasks, not installation failures.\nFollow-up file: " + m.request.Completion.File + "\n\n" + m.todo
		}
	}()
	path := m.request.Completion.File
	if path == "" {
		m.todo = "No follow-up document was supplied."
		return
	}
	info, err := os.Lstat(path)
	if err != nil || !info.Mode().IsRegular() {
		m.todo = "The follow-up file is unavailable. See the installation output and logs."
		return
	}
	file, err := os.Open(path)
	if err != nil {
		m.todo = "Could not open the follow-up file: " + err.Error()
		return
	}
	defer file.Close()
	data, err := io.ReadAll(io.LimitReader(file, 1024*1024+1))
	if err != nil {
		m.todo = "Could not read the follow-up file: " + err.Error()
		return
	}
	truncated := len(data) > 1024*1024
	if truncated {
		data = data[:1024*1024]
	}
	m.todo = strings.Map(func(r rune) rune {
		if r == '\n' || r == '\t' || !unicode.IsControl(r) {
			return r
		}
		return -1
	}, ansi.Strip(string(data)))
	if truncated {
		m.todo += "\n\nPreview truncated; open the file to read the rest."
	}
}

func orgLines(text string, width int, colour bool) []string {
	var lines []string
	for _, line := range strings.Split(text, "\n") {
		line = strings.ReplaceAll(line, "\t", "    ")
		trimmed := strings.TrimSpace(line)
		code := ""
		switch {
		case strings.HasPrefix(strings.ToLower(trimmed), "#+title:"):
			code = "1;38;5;117"
		case strings.HasPrefix(trimmed, "*"):
			code = "1;38;5;141"
			heading := strings.TrimLeft(trimmed, "* ")
			if strings.HasPrefix(heading, "TODO ") {
				code = "1;38;5;213"
			}
			if strings.HasPrefix(heading, "DONE ") {
				code = "38;5;84"
			}
		case strings.HasPrefix(trimmed, "- [X] ") || strings.HasPrefix(trimmed, "- [x] "):
			code = "38;5;84"
		case strings.HasPrefix(trimmed, "- [ ] ") || strings.HasPrefix(trimmed, "- [-] "):
			code = "38;5;213"
		case strings.HasPrefix(trimmed, ":") || strings.HasPrefix(trimmed, "#+"):
			code = "90"
		case strings.Contains(line, "[["):
			code = "38;5;117"
		}
		for _, wrapped := range strings.Split(ansi.Wrap(line, max(1, width), ""), "\n") {
			if code != "" {
				wrapped = paint(wrapped, code, colour)
			}
			lines = append(lines, wrapped)
		}
	}
	return lines
}

// A finished worker must report a terminal state for every selected item.
// Do not turn a missing result into either success or a vague warning.
func (m *Dashboard) itemState(id string) string {
	state := m.progress.States[id]
	switch state {
	case "Installed and verified", "Already present", "Not run", "Failed", "Interrupted":
		return state
	case "Working":
		if !m.done {
			return state
		}
		if m.exitCode == 130 {
			return "Interrupted"
		}
		if m.exitCode != 0 {
			return "Failed"
		}
	case "":
		if !m.done || m.exitCode != 0 {
			return "Not run"
		}
	}
	return "Reporting error"
}

func (m *Dashboard) hasResultFailure() bool {
	if m.progress.Error != "" {
		return true
	}
	for _, it := range m.request.Items {
		switch m.itemState(it.ID) {
		case "Failed", "Interrupted", "Reporting error":
			return true
		}
	}
	return false
}

func (m *Dashboard) completionDetails() string {
	var lines []string
	for _, it := range m.request.Items {
		state := m.itemState(it.ID)
		if state == "Installed and verified" || state == "Already present" {
			continue
		}
		// Unstarted items are already grey in the results list. Do not bury
		// the actual error beneath a repeated explanation for each of them.
		if state == "Not run" {
			hasReason := false
			for _, step := range m.progress.Steps {
				if step.Feature == it.ID && step.State == "Not run" {
					hasReason = true
				}
			}
			if !hasReason {
				continue
			}
		}
		lines = append(lines, "* "+it.Label+" — "+state)
		explained := false
		for _, step := range m.progress.Steps {
			if step.Feature != it.ID || step.State == "Succeeded" {
				continue
			}
			explained = true
			lines = append(lines, step.Label, step.Detail)
			if step.State == "Working" {
				lines = append(lines, "The installer stopped before this step finished. Review its log, then rerun the installer and select this item.")
			}
			if step.Action != "" {
				lines = append(lines, "Next step: "+step.Action)
			}
			if step.Log != "" {
				lines = append(lines, "Log: "+step.Log)
			}
		}
		if !explained {
			switch state {
			case "Reporting error":
				lines = append(lines, "The installer did not report a valid final result. This is an installer bug; retain the logs when reporting it.")
			case "Not run":
				lines = append(lines, "This item was not run. Select it when you next run the installer.")
			default:
				lines = append(lines, "Review the error output and log, then rerun the installer and select this item.")
			}
		}
		lines = append(lines, "")
	}
	if m.progress.Error != "" {
		lines = append(lines, "* Installer error", m.progress.Error)
	} else if m.exitCode != 0 && len(lines) == 0 {
		lines = append(lines, "* Installer error", fmt.Sprintf("The installer exited with status %d. Review the recent output below for the error before retrying.", m.exitCode))
	}
	if len(lines) > 0 {
		if m.progress.Logs != "" {
			lines = append(lines, "Logs and saved results: "+m.progress.Logs)
		}
		if m.exitCode != 0 && m.terminal != nil {
			lines = append(lines, "", "* Recent output", ansi.Strip(m.terminal.Render()))
		}
	}
	return strings.Join(lines, "\n")
}

func (m *Dashboard) completionOutcome() (string, string) {
	if m.progress.Error != "" {
		return "Setup could not finish", m.progress.Error
	}
	failed, notRun, reporting := 0, 0, 0
	for _, it := range m.request.Items {
		switch m.itemState(it.ID) {
		case "Failed", "Interrupted":
			failed++
		case "Reporting error":
			reporting++
		case "Not run":
			notRun++
		}
	}
	if reporting > 0 {
		return "Installer reporting error", "A selected item has no valid final result. Details and log locations are shown on the right."
	}
	if failed > 0 {
		return "Setup incomplete", fmt.Sprintf("%d item(s) failed or were interrupted; %d not run. Completed changes are retained. See the specific error and next step on the right.", failed, notRun)
	}
	if m.exitCode != 0 {
		return "Installer stopped", "Reported successes are retained. See the installer error and recent output on the right."
	}
	if notRun > 0 {
		return "Setup finished", fmt.Sprintf("%d item(s) not run. See their reasons on the right. All other selected items succeeded.", notRun)
	}
	title, text := m.request.Completion.SuccessTitle, m.request.Completion.SuccessText
	if title == "" {
		title = "Setup success!"
	}
	return title, text
}

func (m *Dashboard) completionStatus(lines []string, width int) []string {
	title, text := m.completionOutcome()
	code := "1;38;5;84"
	if m.exitCode != 0 || m.hasResultFailure() {
		code = "1;38;5;203"
	}
	result := append([]string(nil), lines...)
	result = append(result, "", paint(title, code, m.colour), "")
	return append(result, strings.Split(ansi.Wrap(text, max(1, width-4), ""), "\n")...)
}

func (m *Dashboard) scrollCompletion(key string) {
	outputWidth, listWidth := paneWidths(m.width)
	height := max(1, m.height-10)
	if key == "tab" {
		m.resultsFocus = !m.resultsFocus
		return
	}
	offset := &m.todoOffset
	count := len(orgLines(m.todo, outputWidth-4, m.colour))
	if m.resultsFocus {
		offset = &m.statusOffset
		lines, _, _ := m.statusLines()
		if listWidth == 0 {
			listWidth = outputWidth
		}
		count = len(m.completionStatus(lines, listWidth))
	}
	switch key {
	case "down", "j":
		*offset++
	case "up", "k":
		*offset--
	case "pgdown", "space":
		*offset += height
	case "pgup":
		*offset -= height
	case "home":
		*offset = 0
	case "end":
		*offset = count
	}
	*offset = max(0, min(*offset, max(0, count-height)))
}

func (m *Dashboard) completionView(lines []string, listWidth, outputWidth, height int) tea.View {
	title, _ := m.completionOutcome()
	preview := orgLines(m.todo, outputWidth-4, m.colour)
	m.todoOffset = max(0, min(m.todoOffset, max(0, len(preview)-height)))
	previewTitle := m.request.Completion.Title
	if previewTitle == "" {
		previewTitle = "Follow-up tasks"
	}
	if m.completionDetails() != "" {
		previewTitle = "Results and next steps"
	}
	if !m.resultsFocus {
		previewTitle = "› " + previewTitle
	}
	previewTitle += fmt.Sprintf(" · %d/%d", min(m.todoOffset+1, len(preview)), len(preview))
	right := panel(previewTitle, preview[m.todoOffset:], outputWidth, height, m.colour)
	body := columns(right, nil)
	if listWidth > 0 || m.resultsFocus {
		width := listWidth
		if width == 0 {
			width = outputWidth
		}
		results := m.completionStatus(lines, width)
		m.statusOffset = max(0, min(m.statusOffset, max(0, len(results)-height)))
		statusTitle := "Your selection"
		if m.resultsFocus {
			statusTitle = "› " + statusTitle
		}
		left := panel(statusTitle, results[m.statusOffset:], width, height, m.colour)
		if listWidth > 0 {
			body = columns(left, right)
		} else {
			body = columns(left, nil)
		}
	}
	brand := m.request.Brand
	if brand == "" {
		brand = "Installation"
	}
	label := m.request.Completion.Button
	if label == "" {
		label = "Finish"
	}
	label = ansi.Truncate(label, max(1, m.width-8), "…")
	buttonWidth := ansi.StringWidth(label) + 8
	padding := strings.Repeat(" ", max(0, (m.width-buttonWidth)/2))
	blank := paint(strings.Repeat(" ", buttonWidth), "48;5;205;38;5;16", m.colour)
	button := padding + blank + "\n" + padding + paint("    "+label+"    ", "1;48;5;205;38;5;16", m.colour) + "\n" + padding + blank
	text := fit(brandHeader(brand, m.width, m.colour), m.width) + "\n" + fit("  "+title, m.width) + "\n\n" + body + "\n" + button + "\n" + fit("  ↑/↓ PgUp/PgDn: scroll · Tab: switch pane · Enter: finish", m.width)
	v := tea.NewView(text)
	v.AltScreen = true
	v.MouseMode = tea.MouseModeCellMotion
	return v
}

func (m *Dashboard) completionMouse(mouse tea.Mouse, wheel bool) tea.Cmd {
	height := max(1, m.height-10)
	_, listWidth := paneWidths(m.width)
	label := m.request.Completion.Button
	if label == "" {
		label = "Finish"
	}
	buttonWidth := ansi.StringWidth(ansi.Truncate(label, max(1, m.width-8), "…")) + 8
	x := (m.width - buttonWidth) / 2
	if !wheel && mouse.Button == tea.MouseLeft && mouse.Y >= height+5 && mouse.Y < height+8 && mouse.X >= x && mouse.X < x+buttonWidth {
		return tea.Quit
	}
	if mouse.Y >= 3 && mouse.Y < height+5 {
		if listWidth > 0 {
			m.resultsFocus = mouse.X < listWidth
		}
		if wheel {
			key := ""
			if mouse.Button == tea.MouseWheelUp {
				key = "up"
			}
			if mouse.Button == tea.MouseWheelDown {
				key = "down"
			}
			for i := 0; i < 3; i++ {
				m.scrollCompletion(key)
			}
		}
	}
	return nil
}

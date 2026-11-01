package installerui

import (
	tea "charm.land/bubbletea/v2"
	"encoding/json"
	"github.com/charmbracelet/x/ansi"
	"github.com/charmbracelet/x/vt"
	"os"
	"path/filepath"
	"strings"
	"testing"
)

// Layout contracts concern available information and terminal bounds, not
// exact whitespace, colour codes or animation frames.
func TestResponsiveSelectionAndDirectInstall(t *testing.T) {
	r := fixture()
	r.Items[0].Label = "Shell configuration"
	r.Items[0].Note = "Keep your personal shell settings."
	r.Items[0].Operations = []string{"Symlink ~/.bashrc"}
	m, err := New(r, false)
	if err != nil {
		t.Fatal(err)
	}
	for _, width := range []int{40, 80, 120} {
		m.Update(tea.WindowSizeMsg{Width: width, Height: 24})
		view := m.View().Content
		if strings.Contains(view, "What this does") != (width >= 96) {
			t.Fatal("details pane visibility")
		}
		for _, line := range strings.Split(view, "\n") {
			if ansi.StringWidth(line) > width {
				t.Fatalf("line exceeds %d columns", width)
			}
		}
	}
	m.Update(tea.KeyPressMsg{Code: tea.KeyEnter})
	if m.Result.Action != "install" {
		t.Fatal("Enter should start installation")
	}
}

func TestDashboardTerminalAndStatusRemainSeparate(t *testing.T) {
	r := fixture()
	r.Items[0].Label = "Shell"
	r.Items[1].Label = "Editor"
	m := &Dashboard{request: r, width: 120, height: 24, terminal: vt.NewEmulator(75, 16), progress: Progress{Active: "b", States: map[string]string{"a": "Installed and verified", "b": "Working"}}}
	defer m.terminal.Close()
	m.Update(outputMsg("Downloading 10%\rDownloading 90%\r\nPassword: "))
	view := m.View().Content
	if !strings.Contains(view, "Downloading 90%") || !strings.Contains(view, "Password:") || !strings.Contains(view, "✓ Shell") || !strings.Contains(view, "Editor") {
		t.Fatal("terminal output or independent status lost")
	}
	for _, width := range []int{40, 80, 120} {
		m.Update(tea.WindowSizeMsg{Width: width, Height: 24})
		for _, line := range strings.Split(m.View().Content, "\n") {
			if ansi.StringWidth(line) > width {
				t.Fatalf("dashboard exceeds %d columns", width)
			}
		}
	}
}

func fixture() Request {
	return Request{Version: 1, Groups: []Group{{ID: "g", Label: "Group"}}, Items: []Item{{ID: "a", Group: "g", Status: "ready"}, {ID: "b", Group: "g", Parent: "a", Status: "ready", Requires: []string{"a"}}, {ID: "c", Group: "g", Status: "planned"}}}
}
func TestDependencySelectionAndRemoval(t *testing.T) {
	m, e := New(fixture(), false)
	if e != nil {
		t.Fatal(e)
	}
	if e = m.add("b"); e != nil {
		t.Fatal(e)
	}
	if !m.selected["a"] || !m.selected["b"] {
		t.Fatal("dependency missing")
	}
	m.remove("a")
	if len(m.selected) != 0 {
		t.Fatal("dependent retained")
	}
	if m.add("c") == nil {
		t.Fatal("unavailable option accepted")
	}
}
func TestMalformedReferences(t *testing.T) {
	for _, kind := range []string{"missing", "cycle", "parent", "duplicate"} {
		t.Run(kind, func(t *testing.T) {
			r := fixture()
			switch kind {
			case "missing":
				r.Items[1].Requires = []string{"absent"}
			case "cycle":
				r.Items[0].Requires = []string{"b"}
			case "parent":
				r.Items[0].Parent = "b"
			case "duplicate":
				r.Items[2].ID = "a"
			}
			if _, e := New(r, false); e == nil {
				t.Fatal("invalid request accepted")
			}
		})
	}
}
func TestSmallTerminalAndEmptyCatalogue(t *testing.T) {
	m, e := New(Request{Version: 1}, false)
	if e != nil {
		t.Fatal(e)
	}
	m.Update(tea.WindowSizeMsg{Width: 8, Height: 5})
	_ = m.View()
	if cmd := m.finish("cancel"); cmd == nil || m.Result.Action != "cancel" {
		t.Fatal("cancel failed")
	}
}

func TestPartialChoicesSurviveReview(t *testing.T) {
	r := fixture()
	r.Items[0].Options = []Option{{ID: "one", Label: "One"}, {ID: "two", Label: "Two"}}
	r.Items[0].Selected = true
	r.Items[0].Choices = []string{"two"}
	m, e := New(r, false)
	if e != nil {
		t.Fatal(e)
	}
	m.finish("review")
	if got := m.Result.Choices["a"]; len(got) != 1 || got[0] != "two" {
		t.Fatalf("partial choice lost: %v", got)
	}
}

func TestDependenciesPreserveChoicesAndFailuresAreAtomic(t *testing.T) {
	r := fixture()
	r.Items[0].Options = []Option{{ID: "one"}, {ID: "two"}}
	r.Items[0].Selected = true
	r.Items[0].Choices = []string{"two"}
	m, err := New(r, false)
	if err != nil {
		t.Fatal(err)
	}
	if err := m.add("b"); err != nil {
		t.Fatal(err)
	}
	if len(m.choices["a"]) != 1 {
		t.Fatal("dependency reset partial choices")
	}
	m.remove("a")
	m.request.Items[1].Requires = []string{"a", "c"}
	if m.add("b") == nil {
		t.Fatal("unavailable dependency accepted")
	}
	if len(m.selected) != 0 || len(m.choices["a"]) != 0 {
		t.Fatal("failed selection changed other options")
	}
}

func TestSessionKeepsTerminalAndSavesPartialSelection(t *testing.T) {
	r := fixture()
	r.Items[0].Selected = true
	r.Items[0].Options = []Option{{ID: "one"}, {ID: "two"}}
	r.Items[0].Choices = []string{"two"}
	selector, err := New(r, false)
	if err != nil {
		t.Fatal(err)
	}
	m := &Dashboard{request: r, selector: selector, selectionPath: filepath.Join(t.TempDir(), "selection.json"), width: 120, height: 24, terminal: vt.NewEmulator(75, 14)}
	defer m.terminal.Close()
	_, cmd := m.Update(tea.KeyPressMsg{Code: tea.KeyEnter})
	// Selection must start both the worker and the recurring status timer.
	batch, ok := cmd().(tea.BatchMsg)
	if !ok {
		t.Fatal("selection did not start the worker and progress timer")
	}
	started, ticking := false, false
	for _, command := range batch {
		switch command().(type) {
		case startedMsg:
			started = true
		case pulseMsg:
			ticking = true
		}
	}
	if !started || !ticking {
		t.Fatal("missing worker or progress timer after selection")
	}

	m.statePath = filepath.Join(t.TempDir(), "progress.json")
	if err := os.WriteFile(m.statePath, []byte(`{"active":"a","states":{"a":"Working"}}`), 0600); err != nil {
		t.Fatal(err)
	}
	_, next := m.Update(pulseMsg{})
	if m.progress.Active != "a" || m.progress.States["a"] != "Working" || next == nil {
		t.Fatal("timer did not read active status or schedule the next update")
	}
	before, _, _ := m.statusLines()
	m.Update(next())
	after, _, _ := m.statusLines()
	if strings.Join(before, "\n") == strings.Join(after, "\n") {
		t.Fatal("working item did not animate")
	}
	if err := os.WriteFile(m.statePath, []byte(`{"active":"","states":{"a":"Already present"}}`), 0600); err != nil {
		t.Fatal(err)
	}
	m.Update(pulseMsg{})
	_, _, completed := m.statusLines()
	if completed != 1 {
		t.Fatal("completed item was not updated while the worker was running")
	}
	if m.selector != nil || !m.View().AltScreen {
		t.Fatal("terminal ownership lost during preparation")
	}
	data, err := os.ReadFile(m.selectionPath)
	if err != nil {
		t.Fatal(err)
	}
	var result Result
	if json.Unmarshal(data, &result) != nil || len(result.Choices["a"]) != 1 || result.Choices["a"][0] != "two" {
		t.Fatal("partial selection lost")
	}
}

func TestCompletionOrgPreviewScrollsWithoutChangingFile(t *testing.T) {
	path := filepath.Join(t.TempDir(), "TODO.org")
	original := "#+title: Next steps\n* Example tasks\n- [X] Preserved task\n" + strings.Repeat("- [ ] A long follow-up instruction that should wrap in the preview without rewriting the user's file\n", 30)
	if err := os.WriteFile(path, []byte(original), 0600); err != nil {
		t.Fatal(err)
	}
	r := fixture()
	r.Items = r.Items[:1]
	r.Items[0].Label = "Shell"
	r.Completion = Completion{File: path, Title: "~/TODO.org", SuccessTitle: "Setup success!", SuccessText: "Follow the remaining tasks.", Button: "Happy Hacking!"}
	m := &Dashboard{request: r, done: true, width: 120, height: 24, progress: Progress{States: map[string]string{"a": "Already present"}}}
	m.loadCompletion()
	for _, width := range []int{40, 80, 120} {
		m.width = width
		view := m.View().Content
		for _, line := range strings.Split(view, "\n") {
			if ansi.StringWidth(line) > width {
				t.Fatal("completion preview exceeds terminal width")
			}
		}
		if len(strings.Split(view, "\n")) > m.height {
			t.Fatal("completion exceeds terminal height")
		}
		if !strings.Contains(view, "Happy Hacking!") || !strings.Contains(view, "Setup success!") {
			t.Fatal("completion controls missing")
		}
	}
	m.Update(tea.MouseWheelMsg{X: 100, Y: 5, Button: tea.MouseWheelDown})
	if m.todoOffset == 0 {
		t.Fatal("mouse wheel did not scroll preview")
	}
	m.scrollCompletion("end")
	if m.todoOffset == 0 {
		t.Fatal("preview did not scroll")
	}
	m.scrollCompletion("home")
	if m.todoOffset != 0 {
		t.Fatal("preview did not return to beginning")
	}
	m.progress.States["a"] = "Not run"
	title, _ := m.completionOutcome()
	if title == "Setup success!" {
		t.Fatal("skipped operation reported as full success")
	}
	data, _ := os.ReadFile(path)
	if string(data) != original {
		t.Fatal("preview rewrote user document")
	}
}

func TestCompletionExplainsFailuresAndReportingErrors(t *testing.T) {
	m := &Dashboard{done: true, request: Request{Items: []Item{{ID: "sample", Label: "Example item"}}},
		progress: Progress{States: map[string]string{"sample": "Failed"}, Steps: []Operation{
			{Feature: "sample", Label: "Copy files", State: "Succeeded"},
			{Feature: "sample", Label: "Validate configuration", State: "Failed", Detail: "Invalid configuration", Action: "Fix it and retry", Log: "/tmp/example.log"},
		}}}
	title, _ := m.completionOutcome()
	if title != "Setup incomplete" {
		t.Fatal(title)
	}
	details := m.completionDetails()
	for _, want := range []string{"Validate configuration", "Invalid configuration", "Fix it and retry", "/tmp/example.log"} {
		if !strings.Contains(details, want) {
			t.Fatalf("missing %q in %s", want, details)
		}
	}
	m.progress.States["sample"] = "Already present"
	m.progress.Error = "Could not write the follow-up file"
	_, text := m.completionOutcome()
	if text != m.progress.Error {
		t.Fatal(text)
	}
	m.progress.Error = ""
	delete(m.progress.States, "sample")
	title, _ = m.completionOutcome()
	if title != "Installer reporting error" {
		t.Fatal(title)
	}
	m.progress.States["sample"] = "Not run"
	m.progress.Steps = nil
	title, _ = m.completionOutcome()
	if title != "Setup finished" || m.hasResultFailure() {
		t.Fatal("not-run became failure", title)
	}
}

func TestFinishedWorkerCannotHideMissingResults(t *testing.T) {
	m := &Dashboard{request: Request{Items: []Item{{ID: "sample", Label: "Example"}}}}
	m.Update(finishedMsg{})
	if m.exitCode == 0 || m.itemState("sample") != "Reporting error" {
		t.Fatal("missing result lost when exit code changed", m.exitCode, m.itemState("sample"))
	}
}

func TestPreflightFailureIsNotBuriedUnderUnstartedItems(t *testing.T) {
	m := &Dashboard{done: true, exitCode: 1, request: Request{Items: []Item{{ID: "sample", Label: "Unstarted example"}}}}
	details := m.completionDetails()
	if !strings.Contains(details, "Installer error") || strings.Contains(details, "Unstarted example") {
		t.Fatal(details)
	}
}

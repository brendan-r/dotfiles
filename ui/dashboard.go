package installerui

import (
	"encoding/json"
	"fmt"
	"os"
	"os/exec"
	"strings"
	"syscall"
	"time"

	tea "charm.land/bubbletea/v2"
	uv "github.com/charmbracelet/ultraviolet"
	"github.com/charmbracelet/x/ansi"
	"github.com/charmbracelet/x/vt"
	"github.com/creack/pty"
)

// Progress is written atomically by the caller. Command output is deliberately
// separate: a downloaded script cannot impersonate a structured status update.
type Operation struct {
	Feature string `json:"feature"`
	Label   string `json:"label"`
	State   string `json:"state"`
	Detail  string `json:"detail"`
	Log     string `json:"log"`
	Action  string `json:"action"`
}

type Progress struct {
	Steps  []Operation       `json:"steps"`
	Error  string            `json:"error"`
	Logs   string            `json:"logs"`
	Active string            `json:"active"`
	States map[string]string `json:"states"`
}

type outputMsg []byte
type finishedMsg struct{ err error }
type startedMsg struct{ err error }

type Dashboard struct {
	selector                 *Model
	selectionPath            string
	args                     []string
	send                     func(tea.Msg)
	waited                   chan struct{}
	starting                 bool
	todo                     string
	todoOffset, statusOffset int
	resultsFocus             bool
	requestLoaded            bool
	request                  Request
	statePath                string
	progress                 Progress
	terminal                 *vt.Emulator
	process                  *exec.Cmd
	tty                      *os.File
	width, height, tick      int
	colour, done             bool
	stopping                 time.Time
	exitCode                 int
}

// RunDashboard runs exactly the supplied argv in a private controlling terminal.
// The child retains normal password echo control, /dev/tty access and signals.
// All commands stay in that session's process group; cancellation reaps the
// worker and terminates remaining children before returning to the caller.
func RunDashboard(req Request, statePath string, args []string, input, output *os.File, colour bool) (int, error) {
	if len(args) == 0 {
		return 1, fmt.Errorf("dashboard requires a command")
	}
	if _, err := New(req, colour); err != nil {
		return 1, err
	}
	m := &Dashboard{request: req, statePath: statePath, width: 80, height: 24, colour: colour}
	m.terminal = vt.NewEmulator(76, 16)
	return runDashboard(m, args, input, output, false)
}

// RunSession keeps selection, preparation, execution and completion in one
// Bubble Tea program. No shell redraw or terminal handoff occurs between them.
func RunSession(req Request, statePath string, args []string, input, output *os.File, colour bool) (int, error) {
	selector, err := New(req, colour)
	if err != nil {
		return 1, err
	}
	if len(args) == 0 {
		return 1, fmt.Errorf("session requires a command")
	}
	m := &Dashboard{request: req, statePath: statePath, selector: selector, width: 80, height: 24, colour: colour, terminal: vt.NewEmulator(76, 14)}
	return runDashboard(m, args, input, output, true)
}

func runDashboard(m *Dashboard, args []string, input, output *os.File, selectFirst bool) (int, error) {
	m.args = args
	m.selectionPath = m.statePath + ".selection"
	m.waited = make(chan struct{})
	defer m.terminal.Close()
	program := tea.NewProgram(m, tea.WithInput(input), tea.WithOutput(output))
	m.send = program.Send
	if !selectFirst {
		m.starting = true
	}
	_, err := program.Run()
	if m.process != nil && m.process.Process != nil {
		if !m.done {
			_ = syscall.Kill(-m.process.Process.Pid, syscall.SIGKILL)
		}
		<-m.waited
	}
	if m.tty != nil {
		_ = m.tty.Close()
	}
	if err != nil {
		return 1, err
	}
	if !m.done && m.selector == nil {
		return 130, nil
	}
	return m.exitCode, nil
}

// Start the child only from the model's event loop. The following readers send
// immutable messages; all terminal rendering and state updates stay on that loop.
func (m *Dashboard) startWorker() error {
	m.process = exec.Command(m.args[0], m.args[1:]...)
	m.process.Env = append(os.Environ(), "TERM=xterm-256color")
	outputWidth, _ := paneWidths(m.width)
	var err error
	m.tty, err = pty.StartWithSize(m.process, &pty.Winsize{Rows: uint16(max(1, m.height-10)), Cols: uint16(max(1, outputWidth-4))})
	if err != nil {
		return err
	}
	go func() {
		buf := make([]byte, 4096)
		for {
			n, e := m.terminal.Read(buf)
			if n > 0 {
				_, _ = m.tty.Write(buf[:n])
			}
			if e != nil {
				return
			}
		}
	}()
	drained := make(chan struct{})
	go func() {
		defer close(drained)
		buf := make([]byte, 8192)
		for {
			n, e := m.tty.Read(buf)
			if n > 0 {
				m.send(outputMsg(append([]byte(nil), buf[:n]...)))
			}
			if e != nil {
				return
			}
		}
	}()
	go func() {
		err := m.process.Wait()
		_ = syscall.Kill(-m.process.Process.Pid, syscall.SIGTERM)
		select {
		case <-drained:
		case <-time.After(time.Second):
		}
		_ = syscall.Kill(-m.process.Process.Pid, syscall.SIGKILL)
		m.send(finishedMsg{err})
		close(m.waited)
	}()
	return nil
}

func (m *Dashboard) Init() tea.Cmd {
	if m.selector != nil {
		return m.selector.Init()
	}
	if m.starting {
		return tea.Batch(pulse(), func() tea.Msg { return startedMsg{} })
	}
	return pulse()
}

func (m *Dashboard) readProgress() {
	if !m.requestLoaded {
		if data, err := os.ReadFile(m.statePath + ".request"); err == nil {
			var req Request
			if json.Unmarshal(data, &req) == nil {
				if _, err := New(req, m.colour); err == nil {
					m.request = req
					m.requestLoaded = true
				}
			}
		}
	}
	data, err := os.ReadFile(m.statePath)
	if err != nil {
		return
	}
	var next Progress
	if json.Unmarshal(data, &next) == nil {
		m.progress = next
	}
}

func (m *Dashboard) Update(message tea.Msg) (tea.Model, tea.Cmd) {
	if m.selector != nil {
		if size, ok := message.(tea.WindowSizeMsg); ok {
			m.width, m.height = size.Width, size.Height
		}
		_, cmd := m.selector.Update(message)
		switch m.selector.Result.Action {
		case "install":
			result := m.selector.Result
			data, err := json.Marshal(result)
			if err == nil {
				err = os.WriteFile(m.selectionPath, data, 0600)
			}
			if err != nil {
				m.selector.message = "Could not save selection: " + err.Error()
				m.selector.Result = Result{}
				return m, nil
			}
			var items []Item
			for _, it := range m.request.Items {
				if m.selector.selected[it.ID] {
					it.Requires = nil
					it.Parent = ""
					items = append(items, it)
				}
			}
			if len(items) == 0 {
				m.exitCode = 0
				return m, tea.Quit
			}
			m.request.Items = items
			m.selector = nil
			m.starting = true
			outputWidth, _ := paneWidths(m.width)
			m.terminal.Resize(max(1, outputWidth-4), max(1, m.height-10))
			// Start polling when selection ends; the selector does not run a timer.
			return m, tea.Batch(pulse(), func() tea.Msg { return startedMsg{} })
		case "cancel", "interrupt":
			if m.selector.Result.Action == "interrupt" {
				m.exitCode = 130
			}
			return m, tea.Quit
		}
		return m, cmd
	}

	switch msg := message.(type) {
	case tea.MouseClickMsg:
		if m.done {
			return m, m.completionMouse(msg.Mouse(), false)
		}
	case tea.MouseWheelMsg:
		if m.done {
			return m, m.completionMouse(msg.Mouse(), true)
		}
	case startedMsg:
		if err := m.startWorker(); err != nil {
			m.done = true
			m.exitCode = 1
			m.todo = "Could not start installer: " + err.Error()
		}
		return m, nil
	case tea.WindowSizeMsg:
		m.width, m.height = msg.Width, msg.Height
		left, _ := paneWidths(m.width)
		w, h := max(1, left-4), max(1, m.height-10)
		m.terminal.Resize(w, h)
		if m.tty != nil {
			_ = pty.Setsize(m.tty, &pty.Winsize{Rows: uint16(h), Cols: uint16(w)})
		}
	case outputMsg:
		_, _ = m.terminal.Write(msg)
	case pulseMsg:
		m.tick++
		m.readProgress()
		if m.process != nil && m.process.Process != nil && !m.done && !m.stopping.IsZero() && time.Since(m.stopping) > 3*time.Second {
			_ = syscall.Kill(-m.process.Process.Pid, syscall.SIGKILL)
		}
		return m, pulse()
	case finishedMsg:
		m.done = true
		m.readProgress()
		if msg.err != nil {
			m.exitCode = 1
			if e, ok := msg.err.(*exec.ExitError); ok && e.ExitCode() > 0 {
				m.exitCode = e.ExitCode()
			}
		}
		if !m.stopping.IsZero() {
			m.exitCode = 130
		}
		// A zero process exit cannot override a recorded failure or a missing
		// result. Return failure to the caller as well as displaying it.
		if m.exitCode == 0 {
			if m.progress.States == nil {
				m.progress.States = map[string]string{}
			}
			for _, it := range m.request.Items {
				if m.itemState(it.ID) == "Reporting error" {
					m.progress.States[it.ID] = "Reporting error"
				}
			}
			if m.hasResultFailure() {
				m.exitCode = 1
			}
		}
		m.loadCompletion()
	case tea.PasteMsg:
		if !m.done && m.tty != nil {
			m.terminal.Paste(msg.Content)
		}
	case tea.KeyPressMsg:
		if m.done {
			if msg.String() == "enter" || msg.String() == "esc" || msg.String() == "ctrl+c" {
				return m, tea.Quit
			}
			m.scrollCompletion(msg.String())
			return m, nil
		}
		if msg.String() == "ctrl+c" {
			if m.process == nil || m.process.Process == nil {
				m.exitCode = 130
				return m, tea.Quit
			}
			if m.stopping.IsZero() {
				m.stopping = time.Now()
				_ = syscall.Kill(-m.process.Process.Pid, syscall.SIGTERM)
			}
			return m, nil
		}
		// Ordinary keys (including q, Escape, arrows and Enter) belong to the
		// current installer. Never echo input ourselves: passwords stay hidden.
		if m.tty != nil {
			m.terminal.SendKey(uv.KeyPressEvent(msg))
		}
	}
	return m, nil
}

func (m *Dashboard) statusLines() ([]string, int, int) {
	var lines []string
	active, completed := 0, 0
	frames := []string{"⠋", "⠙", "⠹", "⠸", "⠼", "⠴", "⠦", "⠧", "⠇", "⠏"}
	for _, group := range m.request.Groups {
		var rows []string
		for _, it := range m.request.Items {
			if it.Group != group.ID {
				continue
			}
			state := m.itemState(it.ID)
			marker, code := "○", "90"
			switch state {
			case "Installed and verified", "Already present":
				marker, code = "✓", "38;5;84"
				completed++
			case "Failed", "Interrupted", "Reporting error":
				marker, code = "✗", "38;5;203"
			case "Working":
				marker, code = frames[m.tick%len(frames)], "1;38;5;117"
			}
			if it.ID == m.progress.Active {
				active = len(lines) + len(rows) + 1
			}
			rows = append(rows, paint("  "+marker+" "+it.Label, code, m.colour))
			if state == "Failed" || state == "Interrupted" || state == "Reporting error" || (m.done && state == "Not run") {
				rows = append(rows, paint("    "+state, code, m.colour))
			}
			for _, step := range m.progress.Steps {
				if step.Feature != it.ID || (state != "Failed" && state != "Interrupted" && state != "Not run" && state != "Reporting error" && step.State != "Working") {
					continue
				}
				symbol, colour := "○", "90"
				switch step.State {
				case "Succeeded":
					symbol, colour = "✓", "38;5;84"
				case "Failed", "Interrupted":
					symbol, colour = "✗", "38;5;203"
				case "Working":
					if m.done {
						symbol, colour = "✗", "38;5;203"
					} else {
						symbol, colour = frames[m.tick%len(frames)], "38;5;117"
					}
				}
				rows = append(rows, paint("    "+symbol+" "+step.Label, colour, m.colour))
			}
		}
		if len(rows) > 0 {
			lines = append(lines, paint(group.Label, "1;38;5;141", m.colour))
			lines = append(lines, rows...)
		}
	}
	return lines, active, completed
}

func (m *Dashboard) View() tea.View {
	if m.selector != nil {
		return m.selector.View()
	}
	if m.width < 30 || m.height < 10 {
		text := "Resize terminal to 30×10 or larger.\nCtrl+C: stop"
		if m.done {
			text = "Installation stopped. Enter: close"
		}
		v := tea.NewView(text)
		v.AltScreen = true
		return v
	}
	outputWidth, listWidth := paneWidths(m.width)
	height := max(1, m.height-10)
	lines, active, completed := m.statusLines()
	title := "Preparing installation"
	for _, it := range m.request.Items {
		if it.ID == m.progress.Active {
			title = it.Label
		}
	}
	if !m.stopping.IsZero() {
		title = "Stopping installation…"
	}
	if m.done {
		return m.completionView(lines, listWidth, outputWidth, height)
	}
	if m.progress.Active != "" {
		if active < m.statusOffset {
			m.statusOffset = active
		}
		if active >= m.statusOffset+height {
			m.statusOffset = active - height + 1
		}
	}
	m.statusOffset = min(m.statusOffset, max(0, len(lines)-height))
	subtitle := fmt.Sprintf("  %d / %d complete · %s", completed, len(m.request.Items), title)
	frames := []string{"⠋", "⠙", "⠹", "⠸", "⠼", "⠴", "⠦", "⠧", "⠇", "⠏"}
	if m.progress.States == nil {
		subtitle = "  " + frames[m.tick%len(frames)] + " Preparing your installation…"
	}
	fraction := 0
	if len(m.request.Items) > 0 {
		fraction = completed * min(32, max(8, m.width/4)) / len(m.request.Items)
	}
	bar := paint(strings.Repeat("━", fraction), "38;5;84", m.colour) + paint(strings.Repeat("─", min(32, max(8, m.width/4))-fraction), "38;5;60", m.colour)
	terminal := m.terminal.Render()
	if !m.colour {
		terminal = ansi.Strip(terminal)
	}
	output := panel("Live output · "+title, strings.Split(terminal, "\n"), outputWidth, height, m.colour)
	body := columns(output, nil)
	if listWidth > 0 {
		body = columns(panel("Your selection", lines[m.statusOffset:], listWidth, height, m.colour), output)
	}
	brand := m.request.Brand
	if brand == "" {
		brand = "Setting up your machine"
	}
	text := fit(brandHeader(brand, m.width, m.colour), m.width) + "\n" + fit(subtitle, m.width) + "\n" + fit("  "+bar, m.width) + "\n" + body + "\n" + fit("  Type here to answer prompts · Ctrl+C stops installation", m.width)
	v := tea.NewView(text)
	v.AltScreen = true
	pos := m.terminal.CursorPosition()
	x := pos.X + 2
	if listWidth > 0 {
		x += listWidth + 1
	}
	v.Cursor = tea.NewCursor(x, pos.Y+4)
	return v
}

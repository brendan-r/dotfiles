package main

import (
	tea "charm.land/bubbletea/v2"
	"encoding/json"
	"fmt"
	ui "github.com/brendan-r/installer-ui"
	"os"
)

func main() {
	if len(os.Args) < 2 {
		die(fmt.Errorf("usage: installer-ui select|session|dashboard"))
	}
	mode := os.Args[1]
	req := ui.Request{Version: 1}
	if mode != "select" && mode != "dashboard" && mode != "session" {
		die(fmt.Errorf("unknown mode"))
	}
	if err := json.NewDecoder(os.Stdin).Decode(&req); err != nil {
		die(err)
	}
	if mode == "dashboard" || mode == "session" {
		if len(os.Args) < 5 || os.Args[3] != "--" {
			die(fmt.Errorf("dashboard requires STATE_FILE -- COMMAND [ARGS]"))
		}
		tty, err := os.OpenFile("/dev/tty", os.O_RDWR, 0)
		if err != nil {
			die(err)
		}
		run := ui.RunDashboard
		if mode == "session" {
			run = ui.RunSession
		}
		code, err := run(req, os.Args[2], os.Args[4:], tty, tty, os.Getenv("NO_COLOR") == "")
		tty.Close()
		if err != nil {
			die(err)
		}
		os.Exit(code)
	}
	model, err := ui.New(req, os.Getenv("NO_COLOR") == "")
	if err != nil {
		die(err)
	}
	tty, err := os.OpenFile("/dev/tty", os.O_RDWR, 0)
	if err != nil {
		die(err)
	}
	defer tty.Close()
	program := tea.NewProgram(model, tea.WithInput(tty), tea.WithOutput(tty))
	_, err = program.Run()
	if err != nil {
		die(err)
	}
	if model.Result.Action == "interrupt" {
		os.Exit(130)
	}
	if err = json.NewEncoder(os.Stdout).Encode(model.Result); err != nil {
		die(err)
	}
}
func die(err error) { fmt.Fprintln(os.Stderr, "installer-ui:", err); os.Exit(1) }

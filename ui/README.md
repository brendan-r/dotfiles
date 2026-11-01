# Installer UI

A standalone Go library and JSON CLI built with Bubble Tea. This module has no dependency on the enclosing dotfiles repository. Build with `go build ./cmd/installer-ui`; test with `go test ./...` in the disposable test environment.

`installer-ui select` reads a version-1 JSON request from stdin and returns `{ "action": "install" | "cancel", "selected": ["stable-id"] }` on stdout. Terminal interaction uses `/dev/tty`. Ctrl+C exits 130. Requests contain `title`, ordered `groups` (`id`, `label`) and ordered `items` (`id`, `label`, `group`, optional `parent`, `requires`, `note`, `operations` (descriptive strings), `selected`, and `status`: ready/review/planned). Dependencies are selected automatically; deselecting a prerequisite also deselects its dependants. Unavailable entries remain visible but cannot be selected.

`installer-ui session STATE_FILE -- COMMAND [ARGS]` keeps selection, preparation, the dashboard and completion inside one terminal session. It writes the chosen `Result` to `STATE_FILE.selection` before starting the command. The command reads that file, validates its plan, and may atomically publish a replacement request at `STATE_FILE.request` to include prerequisite steps. No installation command runs before selection is accepted. Cancellation before starting returns without running the worker.

Requests may include `brand` and `completion`: `file` (a regular UTF-8 text/Org file to preview), `title`, `success_title`, `success_text`, and `button`. These are caller-supplied presentation data, not dotfiles-specific library behavior. Completion preserves the status list position, highlights Org headings, checkboxes and links, wraps long lines on screen, and never rewrites the file. Reads are bounded to 1 MiB and control sequences are stripped. Success wording appears only when the command succeeded and every item reports successful completion. Failed runs name the unsuccessful step, its recovery action and its log path, followed by recent terminal output. Normal manual setup does not turn success into a warning.

On completion, arrows, Page Up/Down and Home/End scroll the preview; Tab changes the focused pane. The mouse wheel scrolls the pane under the pointer. On narrow terminals, Tab switches between results and preview. Enter or clicking the completion button closes the UI and returns the worker's exit code.

`installer-ui dashboard STATE_FILE -- COMMAND [ARGS]` reads the same request on stdin and runs the given argv in a private PTY. It displays grouped feature statuses on the left and live terminal output on the right. Ordinary keys and paste go to the child; password echo remains controlled by the child's terminal settings. Ctrl+C terminates the worker process group, with a three-second kill fallback. Enter closes the completed dashboard and returns the command's exit code. The caller prints its final summary after the alternate screen closes.

The caller atomically replaces `STATE_FILE` with `{"active":"item-id","states":{"item-id":"Working"}}`. Supported item statuses are `Not run`, `Working`, `Installed and verified`, `Already present`, `Failed`, and `Interrupted`. Success is green, failure/interruption is red, not-run is grey, and working items animate. An unknown or missing result after a successful worker exit is an explicit reporting error. Output cannot change these statuses. The worker and its children must remain in the supplied process group (no daemonizing or job-control groups). The dashboard does not interpret shell, package names, YAML or log files. Terminal output scrolls automatically; persistent logs belong to the caller. The left status sidebar hides below 96 columns, leaving the active item and completion count above the terminal.

`NO_COLOR` disables colour. Space or x toggles, arrows/j/k navigate, Enter starts installation, and Escape cancels. Page Up/Down and Home/End navigate longer lists.

Items may contain `options` (`id`, `label`) for independently selectable children of a bundle. `choices` supplies a partial initial selection. Results include the selected option IDs in a `choices` map keyed by item ID. Parent markers show partial selection. Press `c` to clear all selections. Wide terminals show a description/operations sidebar; below 96 columns it disappears.

Build all platforms with `python3 build.py /absolute/path/to/go /output/directory`. The script compiles but never runs candidate code on the host. Run the emitted `test-bin` executables in disposable VMs. The dotfiles harness includes them automatically.

Progress may also include `steps`, an ordered array of `{feature, label, state,
detail, log, action}`. Step states are `Working`, `Succeeded`, `Failed`,
`Interrupted`, or `Not run`. The UI expands failed items to show completed and
failed steps separately. `error` describes a finalisation error independently of
successful item results; `logs` supplies the caller's result directory. These are
plain data supplied by the caller: the library does not invent retry commands or
read arbitrary log files. A recorded failure results in a nonzero UI exit even if
the worker incorrectly exits zero.

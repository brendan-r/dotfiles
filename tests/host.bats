#!/bin/bash
# Host checks parse candidate files; they never source or execute them.
function static__shell__scripts_parse_without_syntax_errors { # @test
    while IFS= read -r file; do
        /bin/bash -n "$DOTFILES_ROOT/$file"
    done < "$DOTFILES_SHELL_MANIFEST"
}
function static__shell__scripts_pass_shellcheck { # @test
    if [ "$DOTFILES_HOST_MODE" = host-syntax ]; then skip 'syntax-only run'; fi
    if [ -z "$DOTFILES_SHELLCHECK" ]; then
        echo 'ShellCheck not found. Install a trusted copy or set SHELLCHECK.'
        return 1
    fi
    files=()
    while IFS= read -r file; do files+=("$file"); done < "$DOTFILES_SHELL_MANIFEST"
    cd "$DOTFILES_ROOT" || return
    "$DOTFILES_SHELLCHECK" --norc --external-sources --severity=style "${files[@]}"
}

# This Python check reads inert data and a temporary index; no UI code executes.
function static__ui__build_manifest_checks_staged_contents { # @test
    python3 "$DOTFILES_ROOT/tests/test_ui_build_check.py"
}

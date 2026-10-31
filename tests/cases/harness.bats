#!/bin/bash
setup() {
    [ -r /etc/dotfiles-test-image ] && [ "${DOTFILES_TEST_GUEST:-}" = 1 ]
}

function runner__processes__output_streams_before_process_exits { # @test
    python3 "$DOTFILES_CANDIDATE/tests/helpers/harness-probe.py" streaming
}

function runner__processes__timeout_stops_child { # @test
    python3 "$DOTFILES_CANDIDATE/tests/helpers/harness-probe.py" silent_timeout
}

function runner__processes__interruption_stops_child_and_preserves_partial_log { # @test
    python3 "$DOTFILES_CANDIDATE/tests/helpers/harness-probe.py" interrupted_stream
}

function runner__processes__failed_process_preserves_exit_status_and_log { # @test
    python3 "$DOTFILES_CANDIDATE/tests/helpers/harness-probe.py" transport_failure
}

function runner__suites__failures_continue_and_interruptions_stop_remaining_suites { # @test
    python3 "$DOTFILES_CANDIDATE/tests/helpers/harness-probe.py" continuation
}

function runner__output__results_and_diagnostics_remain_readable_in_terminal_and_logs { # @test
    python3 "$DOTFILES_CANDIDATE/tests/helpers/harness-probe.py" formatting
}

function runner__vms__cleanup_errors_and_unconfirmed_stops_are_reported { # @test
    python3 "$DOTFILES_CANDIDATE/tests/helpers/harness-probe.py" cleanup_failure
}

function runner__vms__success_deletes_guest_and_failures_retain_it { # @test
    python3 "$DOTFILES_CANDIDATE/tests/helpers/harness-probe.py" vm_lifecycle
}

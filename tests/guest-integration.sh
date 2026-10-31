#!/bin/bash
set -eo pipefail
[ -r /etc/dotfiles-test-image ] || { echo 'Run through tests/run in a disposable VM.' >&2; exit 2; }
export DOTFILES_TEST_GUEST=1
mode=$1
export DOTFILES_FIXTURE_URL=$2 DOTFILES_REVISION=$3
format=$4
export DOTFILES_TEST_COLOR=$5
export BATS_TEST_NAME_PREFIX="[$6] "
# Distinguish setup/transport failure from a completed Bats run with failed assertions.
completion=$7
# The outer host terminal decides; the guest transport always has a PTY.
export DOTFILES_TEST_INTERACTIVE=${8:-0} DOTFILES_TEST_COLUMNS=${9:-80}
stage=$(mktemp -d)
trap 'rm -rf "$stage"' EXIT
/usr/bin/curl -qfsS --max-time 30 "$DOTFILES_FIXTURE_URL/candidate.tar.gz" -o "$stage/candidate.tar.gz"
mkdir "$stage/candidate with spaces"
tar -xzf "$stage/candidate.tar.gz" -C "$stage/candidate with spaces"
DOTFILES_CANDIDATE=$(cd -P "$stage/candidate with spaces" && pwd)
export DOTFILES_CANDIDATE
case "$mode" in unit|integration) ;; *) echo "Unknown guest suite: $mode" >&2; exit 2 ;; esac
formatter=tap
if [ "$format" = pretty ]; then formatter="$DOTFILES_CANDIDATE/tests/format-pretty"; fi
cases=("$DOTFILES_CANDIDATE/tests/cases/behavior.bats" "$DOTFILES_CANDIDATE/tests/cases/startup.bats")
if [ "$mode" = integration ]; then cases+=("$DOTFILES_CANDIDATE/tests/cases/integration.bats"); fi
cases+=("$DOTFILES_CANDIDATE/tests/cases/harness.bats")
code=0
/bin/bash "$DOTFILES_CANDIDATE/tests/vendor/bats-core/bin/bats" --timing --print-output-on-failure \
    --formatter "$formatter" "${cases[@]}" || code=$?
printf '%s\n' "$code" > "$completion"
exit "$code"

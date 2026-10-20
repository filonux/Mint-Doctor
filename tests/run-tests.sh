#!/usr/bin/env bash
# Runs tests/test.sh the same way CI does, so a local run and a CI run behave alike.
#
# Why this wrapper exists instead of calling tests/test.sh directly:
#   * A few end-to-end tests drop privileges to the unprivileged user "nobody"
#     with `runuser`, which only works when the suite itself runs as root.
#   * That user must be able to read the script. A repository checked out under
#     a private home directory (mode 750, the default on Ubuntu/Mint and on some
#     CI images) is unreachable for it, and those tests then fail with
#     "Permission denied" even though the code is fine.
# So the repository is copied to a world-readable temporary directory and the
# suite runs from there as root. Nothing outside that copy and the suite's own
# temporary files is touched, and no real repair is ever applied (the suite only
# runs the script with --dry-run).
#
# Usage (from anywhere):  bash tests/run-tests.sh
# Exit status:            that of tests/test.sh (number of failed tests)
set -euo pipefail

repo_root="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"

as_root() {
    if [[ $EUID -eq 0 ]]; then
        "$@"
    else
        sudo "$@"
    fi
}

if [[ $EUID -ne 0 ]] && ! command -v sudo >/dev/null 2>&1; then
    echo "error: this wrapper needs root or sudo to run the test suite." >&2
    exit 2
fi

# tests/test.sh reports a missing tool as a plain failure, which is misleading:
# check up front and say what is actually wrong.
missing=()
for tool in python3 runuser script timeout; do
    # $1 is meant to expand in the inner shell, hence the single quotes.
    # shellcheck disable=SC2016
    as_root bash -c 'command -v "$1" >/dev/null 2>&1' _ "$tool" || missing+=("$tool")
done
if ((${#missing[@]})); then
    echo "error: required tool(s) not found: ${missing[*]}" >&2
    echo "       (runuser/script/timeout come from util-linux and coreutils)" >&2
    exit 2
fi

stage="$(mktemp -d)"
cleanup() { as_root rm -rf "$stage"; }
trap cleanup EXIT

# Copy the working tree without VCS metadata, then make it readable for "nobody".
tar -C "$repo_root" --exclude=.git -cf - . | tar -C "$stage" -xf -
chmod -R a+rX "$stage"

echo "Running tests/test.sh from a world-readable copy of the repository"
as_root bash "$stage/tests/test.sh"

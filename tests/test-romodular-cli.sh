#!/bin/sh
# Integration coverage for the read-only workspace CLI.  Every repository is
# an isolated temporary worktree; the test never uses the developer workspace.
set -eu

REPOSITORY_ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
CLI="$REPOSITORY_ROOT/scripts/romodular.sh"
MANIFEST="$REPOSITORY_ROOT/.romodular/workspace/repositories.txt"
TEST_ROOT=$(mktemp -d "${TMPDIR:-/tmp}/romodular-cli.XXXXXX")
trap 'rm -rf "$TEST_ROOT"' EXIT HUP INT TERM

while IFS='|' read -r name origin || [ -n "$name" ]; do
    case "$name" in ''|'#'*) continue ;; esac
    repository="$TEST_ROOT/$name"
    mkdir -p "$repository"
    git -C "$repository" init -q -b main
    git -C "$repository" config user.email "romodular-cli-test@example.invalid"
    git -C "$repository" config user.name "RoModular CLI test"
    : > "$repository/tracked.txt"
    git -C "$repository" add tracked.txt
    git -C "$repository" commit -qm "Initial fixture"
    git -C "$repository" remote add origin "$origin"
done < "$MANIFEST"

printf 'dirty\n' > "$TEST_ROOT/Foundation/untracked.txt"
rm -rf "$TEST_ROOT/MIDILAR"

doctor_output=$($CLI doctor --root "$TEST_ROOT")
status_output=$($CLI status --root "$TEST_ROOT")
printf '%s\n' "$doctor_output" | grep -F "workspace marker: absent (manifest layout accepted)" >/dev/null
printf '%s\n' "$status_output" | grep -E '^Foundation: .*dirty=1 .*origin=ok .*upstream=none' >/dev/null
printf '%s\n' "$status_output" | grep -Fx 'MIDILAR: missing' >/dev/null

before=$(git -C "$TEST_ROOT/RoModular" rev-parse HEAD)
before_branch=$(git -C "$TEST_ROOT/RoModular" branch --show-current)
before_status=$(git -C "$TEST_ROOT/RoModular" status --porcelain)
$CLI sync --dry-run --root "$TEST_ROOT" >/dev/null
after=$(git -C "$TEST_ROOT/RoModular" rev-parse HEAD)
after_branch=$(git -C "$TEST_ROOT/RoModular" branch --show-current)
after_status=$(git -C "$TEST_ROOT/RoModular" status --porcelain)
[ "$before" = "$after" ]
[ "$before_branch" = "$after_branch" ]
[ "$before_status" = "$after_status" ]

if $CLI sync --root "$TEST_ROOT" >/dev/null 2>&1; then
    printf '%s\n' 'sync without --dry-run unexpectedly succeeded' >&2
    exit 1
fi

printf '%s\n' 'RoModular CLI shell integration tests passed.'

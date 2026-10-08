#!/bin/sh
# RoModular workspace CLI.  It orchestrates checked-in repository workflows;
# it never replaces their build, test, or package scripts.
set -eu

ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
MANIFEST="$ROOT/.romodular/workspace/repositories.txt"
WORKSPACE_ROOT=$(CDPATH= cd -- "$ROOT/.." && pwd)

usage() {
    cat <<'EOF'
Usage: romodular.sh <command> [options]

Commands:
  doctor [--root <path>]  Inspect workspace repositories and required tools.
  status [--root <path>]  Report branch, worktree state, and upstream drift.
  sync --dry-run [--root <path>]
                          Show only the fast-forward updates that sync would run.

This CLI delegates builds, tests, packages, and firmware workflows to each
repository's checked-in scripts and presets.
EOF
}

fail() { printf 'error: %s\n' "$1" >&2; exit 1; }
command_name=${1:-}
[ "$command_name" != "-h" ] && [ "$command_name" != "--help" ] || { usage; exit 0; }
[ -n "$command_name" ] || { usage >&2; exit 2; }
shift
DRY_RUN=0
while [ "$#" -gt 0 ]; do
    case "$1" in
        --root) [ "$#" -ge 2 ] || fail "--root requires a path"; WORKSPACE_ROOT=$2; shift 2 ;;
        --dry-run) DRY_RUN=1; shift ;;
        -h|--help) usage; exit 0 ;;
        *) fail "unknown option: $1" ;;
    esac
done

[ -f "$MANIFEST" ] || fail "repository manifest not found: $MANIFEST"
case "$WORKSPACE_ROOT" in /*) ;; *) WORKSPACE_ROOT=$(pwd)/$WORKSPACE_ROOT ;; esac
[ -d "$WORKSPACE_ROOT" ] || fail "workspace directory not found: $WORKSPACE_ROOT"
WORKSPACE_ROOT=$(CDPATH= cd -- "$WORKSPACE_ROOT" && pwd)

normalize_origin() {
    printf '%s' "$1" | sed 's#/$##; s#\.git$##'
}

inspect() {
    command -v git >/dev/null 2>&1 || fail "Git is required but was not found on PATH"
    while IFS='|' read -r name expected_origin || [ -n "$name" ]; do
        name=$(printf '%s' "$name" | tr -d '\r')
        case "$name" in ''|'#'*) continue ;; esac
        path="$WORKSPACE_ROOT/$name"
        if ! git -C "$path" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
            printf '%s: missing\n' "$name"; continue
        fi
        actual_origin=$(git -C "$path" remote get-url origin 2>/dev/null || printf 'missing')
        if [ "$(normalize_origin "$actual_origin")" = "$(normalize_origin "$expected_origin")" ]; then
            origin_status=ok
        else
            origin_status=mismatch
        fi
        branch=$(git -C "$path" branch --show-current)
        short_sha=$(git -C "$path" rev-parse --short HEAD)
        dirty=$(git -C "$path" status --porcelain | wc -l | tr -d ' ')
        upstream=$(git -C "$path" rev-parse --abbrev-ref '@{upstream}' 2>/dev/null || printf 'none')
        drift=$(git -C "$path" rev-list --left-right --count '@{upstream}...HEAD' 2>/dev/null || printf 'unknown')
        set -- $drift
        if [ "$#" -eq 2 ]; then
            drift="behind=$1 ahead=$2 (cached)"
        else
            drift="behind/ahead=unknown (cached)"
        fi
        printf '%s: ref=%s sha=%s dirty=%s origin=%s upstream=%s %s\n' "$name" "${branch:-detached}" "$short_sha" "$dirty" "$origin_status" "$upstream" "$drift"
    done < "$MANIFEST"
}

workspace_marker() {
    if [ -f "$WORKSPACE_ROOT/.romodular-workspace" ]; then
        printf 'workspace marker: present\n'
    else
        printf 'workspace marker: absent (manifest layout accepted)\n'
    fi
}

case "$command_name" in
    doctor)
        printf 'RoModular workspace: %s\n' "$WORKSPACE_ROOT"
        workspace_marker
        inspect
        for tool in cmake ninja doxygen; do
            if command -v "$tool" >/dev/null 2>&1; then printf '%s: available\n' "$tool"; else printf '%s: unavailable\n' "$tool"; fi
        done
        ;;
    status) inspect ;;
    sync)
        [ "$DRY_RUN" -eq 1 ] || fail "sync is preview-only in this release; rerun with --dry-run"
        printf 'Sync plan only: no repositories changed. A future release may execute only clean, fast-forward updates.\n'
        inspect
        ;;
    *) usage >&2; exit 2 ;;
esac

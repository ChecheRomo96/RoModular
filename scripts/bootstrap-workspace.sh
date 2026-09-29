#!/bin/sh

set -eu

SCRIPT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
ROMODULAR_ROOT=$(CDPATH= cd -- "$SCRIPT_DIR/.." && pwd)
ROMODULAR_PARENT=$(dirname -- "$ROMODULAR_ROOT")
WORKSPACE_MARKER_NAME=.romodular-workspace
if [ -f "$ROMODULAR_PARENT/$WORKSPACE_MARKER_NAME" ]; then
    DEFAULT_WORKSPACE_ROOT=$ROMODULAR_PARENT
else
    DEFAULT_WORKSPACE_ROOT="$ROMODULAR_PARENT/RoModularWorkspace"
fi
DEFAULT_MANIFEST="$ROMODULAR_ROOT/.romodular/workspace/repositories.txt"
WORKSPACE_AGENTS_TEMPLATE="$ROMODULAR_ROOT/.romodular/workspace/AGENTS.md"
WORKSPACE_CLAUDE_TEMPLATE="$ROMODULAR_ROOT/.romodular/workspace/CLAUDE.md"

WORKSPACE_ROOT=${ROMODULAR_WORKSPACE_ROOT:-$DEFAULT_WORKSPACE_ROOT}
MANIFEST=$DEFAULT_MANIFEST
FORCE_CONFIG=0
DRY_RUN=0

usage() {
    printf '%s\n' \
        "Usage: $0 [--root <path>] [--manifest <path>] [--force-config] [--dry-run]" \
        "" \
        "Clone the RoModular repositories and configure a shared AI workspace." \
        "" \
        "Options:" \
        "  --root <path>      Workspace root. Defaults to a RoModularWorkspace sibling." \
        "  --manifest <path>  Alternate directory|origin repository manifest." \
        "  --force-config     Replace existing workspace agent adapters." \
        "  --dry-run          Print planned actions without changing the filesystem." \
        "  -h, --help         Show this help text."
}

fail() {
    printf 'error: %s\n' "$1" >&2
    exit 1
}

while [ "$#" -gt 0 ]; do
    case "$1" in
        --root)
            [ "$#" -ge 2 ] || fail "--root requires a path"
            WORKSPACE_ROOT=$2
            shift 2
            ;;
        --manifest)
            [ "$#" -ge 2 ] || fail "--manifest requires a path"
            MANIFEST=$2
            shift 2
            ;;
        --force-config)
            FORCE_CONFIG=1
            shift
            ;;
        --dry-run)
            DRY_RUN=1
            shift
            ;;
        -h|--help)
            usage
            exit 0
            ;;
        *)
            fail "unknown argument: $1"
            ;;
    esac
done

command -v git >/dev/null 2>&1 || fail "Git is required but was not found on PATH"
[ -f "$MANIFEST" ] || fail "repository manifest not found: $MANIFEST"
[ -f "$WORKSPACE_AGENTS_TEMPLATE" ] || fail "workspace AGENTS template not found"
[ -f "$WORKSPACE_CLAUDE_TEMPLATE" ] || fail "workspace CLAUDE template not found"

case "$WORKSPACE_ROOT" in
    /*) ;;
    *) WORKSPACE_ROOT=$(pwd)/$WORKSPACE_ROOT ;;
esac

printf 'RoModular workspace: %s\n' "$WORKSPACE_ROOT"

if [ "$DRY_RUN" -eq 1 ]; then
    printf '[dry-run] create workspace directory if missing\n'
else
    mkdir -p "$WORKSPACE_ROOT"
fi

FAILED=0
WORKSPACE_MARKER="$WORKSPACE_ROOT/$WORKSPACE_MARKER_NAME"

if [ -e "$WORKSPACE_MARKER" ] && [ ! -f "$WORKSPACE_MARKER" ]; then
    printf 'error: %s exists but is not a regular file\n' "$WORKSPACE_MARKER" >&2
    FAILED=1
elif [ "$DRY_RUN" -eq 1 ]; then
    printf '[dry-run] create workspace marker\n'
elif [ ! -e "$WORKSPACE_MARKER" ]; then
    printf '%s\n' 'RoModular workspace format 1' > "$WORKSPACE_MARKER"
fi

while IFS='|' read -r REPOSITORY_NAME REPOSITORY_ORIGIN || [ -n "$REPOSITORY_NAME" ]; do
    REPOSITORY_NAME=$(printf '%s' "$REPOSITORY_NAME" | tr -d '\r')
    REPOSITORY_ORIGIN=$(printf '%s' "$REPOSITORY_ORIGIN" | tr -d '\r')

    case "$REPOSITORY_NAME" in
        ''|'#'*) continue ;;
    esac

    if [ -z "$REPOSITORY_ORIGIN" ]; then
        printf 'error: missing origin for %s\n' "$REPOSITORY_NAME" >&2
        FAILED=1
        continue
    fi

    REPOSITORY_PATH="$WORKSPACE_ROOT/$REPOSITORY_NAME"

    if [ -e "$REPOSITORY_PATH" ]; then
        if ! git -C "$REPOSITORY_PATH" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
            printf 'error: %s exists but is not a Git worktree\n' "$REPOSITORY_PATH" >&2
            FAILED=1
            continue
        fi

        ACTUAL_ORIGIN=$(git -C "$REPOSITORY_PATH" remote get-url origin 2>/dev/null || true)
        if [ "$ACTUAL_ORIGIN" != "$REPOSITORY_ORIGIN" ]; then
            printf 'error: %s has unexpected origin: %s\n' \
                "$REPOSITORY_NAME" "${ACTUAL_ORIGIN:-<missing>}" >&2
            printf '       expected: %s\n' "$REPOSITORY_ORIGIN" >&2
            FAILED=1
            continue
        fi

        printf 'present: %s (left unchanged)\n' "$REPOSITORY_NAME"
        continue
    fi

    if [ "$DRY_RUN" -eq 1 ]; then
        printf '[dry-run] clone %s into %s\n' "$REPOSITORY_ORIGIN" "$REPOSITORY_PATH"
    else
        printf 'cloning: %s\n' "$REPOSITORY_NAME"
        if ! git clone --recurse-submodules "$REPOSITORY_ORIGIN" "$REPOSITORY_PATH"; then
            printf 'error: clone failed for %s\n' "$REPOSITORY_NAME" >&2
            FAILED=1
        fi
    fi
done < "$MANIFEST"

install_workspace_file() {
    SOURCE_FILE=$1
    DESTINATION_FILE=$2
    DISPLAY_NAME=$3

    if [ -e "$DESTINATION_FILE" ] && [ ! -f "$DESTINATION_FILE" ]; then
        printf 'error: %s exists but is not a regular file\n' "$DESTINATION_FILE" >&2
        FAILED=1
    elif [ -f "$DESTINATION_FILE" ] && cmp -s "$SOURCE_FILE" "$DESTINATION_FILE"; then
        printf 'configured: %s is current\n' "$DISPLAY_NAME"
    elif [ -e "$DESTINATION_FILE" ] && [ "$FORCE_CONFIG" -ne 1 ]; then
        printf 'error: %s already exists and differs from the template\n' \
            "$DESTINATION_FILE" >&2
        printf '       rerun with --force-config to replace it\n' >&2
        FAILED=1
    elif [ "$DRY_RUN" -eq 1 ]; then
        printf '[dry-run] install %s\n' "$DISPLAY_NAME"
    else
        mkdir -p "$(dirname -- "$DESTINATION_FILE")"
        cp "$SOURCE_FILE" "$DESTINATION_FILE"
        printf 'configured: %s\n' "$DESTINATION_FILE"
    fi
}

install_workspace_file \
    "$WORKSPACE_AGENTS_TEMPLATE" \
    "$WORKSPACE_ROOT/AGENTS.md" \
    "workspace AGENTS.md"
install_workspace_file \
    "$WORKSPACE_CLAUDE_TEMPLATE" \
    "$WORKSPACE_ROOT/.claude/CLAUDE.md" \
    "workspace .claude/CLAUDE.md"

if command -v codex >/dev/null 2>&1; then
    CODEX_VERSION=$(codex --version 2>/dev/null || true)
    printf 'Codex available: %s\n' "${CODEX_VERSION:-version unavailable}"
    printf "  launch: codex -C '%s'\n" "$WORKSPACE_ROOT"
else
    printf 'Codex not found; workspace files were configured without installing it.\n'
fi

if command -v claude >/dev/null 2>&1; then
    CLAUDE_VERSION=$(claude --version 2>/dev/null || true)
    printf 'Claude Code available: %s\n' "${CLAUDE_VERSION:-version unavailable}"
    printf "  launch: cd '%s' && claude\n" "$WORKSPACE_ROOT"
else
    printf 'Claude Code not found; workspace files were configured without installing it.\n'
fi

if [ "$FAILED" -ne 0 ]; then
    fail "workspace setup completed with errors"
fi

printf 'Workspace setup complete. Existing repositories were not updated.\n'

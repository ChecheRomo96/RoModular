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

WORKSPACE_ROOT=${ROMODULAR_WORKSPACE_ROOT:-$DEFAULT_WORKSPACE_ROOT}
MANIFEST=$DEFAULT_MANIFEST
DRY_RUN=0

usage() {
    printf '%s\n' \
        "Usage: $0 [--root <path>] [--manifest <path>] [--dry-run]" \
        "" \
        "Clone the RoModular repositories into a shared workspace." \
        "" \
        "Options:" \
        "  --root <path>      Workspace root. Defaults to a RoModularWorkspace sibling." \
        "  --manifest <path>  Alternate directory|origin repository manifest." \
        "  --dry-run          Print planned actions without changing the filesystem." \
        "  -h, --help         Show this help text."
}

fail() {
    printf 'error: %s\n' "$1" >&2
    exit 1
}

normalize_git_origin() {
    printf '%s' "$1" | sed -e 's#/*$##' -e 's#\.git$##'
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

case "$WORKSPACE_ROOT" in
    /*) ;;
    # Windows drive paths from Git Bash, e.g. C:\Users\me.
    [A-Za-z]:*) WORKSPACE_ROOT=$(cygpath -u "$WORKSPACE_ROOT") ;;
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
        NORMALIZED_ACTUAL_ORIGIN=$(normalize_git_origin "$ACTUAL_ORIGIN")
        NORMALIZED_EXPECTED_ORIGIN=$(normalize_git_origin "$REPOSITORY_ORIGIN")
        if [ "$NORMALIZED_ACTUAL_ORIGIN" != "$NORMALIZED_EXPECTED_ORIGIN" ]; then
            printf 'error: %s has unexpected origin: %s\n' \
                "$REPOSITORY_NAME" "${ACTUAL_ORIGIN:-<missing>}" >&2
            printf '       expected: %s\n' "$REPOSITORY_ORIGIN" >&2
            FAILED=1
            continue
        fi

        if [ "$REPOSITORY_NAME" = CPSTL ]; then
            STATUS=$(git -C "$REPOSITORY_PATH" status --porcelain) || fail "cannot inspect CPSTL status"
            BRANCH=$(git -C "$REPOSITORY_PATH" symbolic-ref --quiet --short HEAD || true)
            [ -z "$STATUS" ] && [ "$BRANCH" = main ] || fail "CPSTL must be clean and on main to update; preserve local work before retrying"
            if [ "$DRY_RUN" -eq 1 ]; then
                printf '[dry-run] fetch CPSTL main and fast-forward to origin/main\n'
                continue
            fi
            git -c pack.writeReverseIndex=false -C "$REPOSITORY_PATH" fetch origin '+refs/heads/main:refs/remotes/origin/main' || fail "fetch failed for CPSTL"
            git -C "$REPOSITORY_PATH" merge-base --is-ancestor HEAD origin/main || fail "CPSTL has local commits; cannot update to origin/main"
            git -C "$REPOSITORY_PATH" merge --ff-only origin/main || fail "fast-forward failed for CPSTL"
            printf 'updated: CPSTL (origin/main)\n'
            continue
        fi
        printf 'present: %s (left unchanged)\n' "$REPOSITORY_NAME"
        continue
    fi

    if [ "$DRY_RUN" -eq 1 ]; then
        printf '[dry-run] clone %s into %s\n' "$REPOSITORY_ORIGIN" "$REPOSITORY_PATH"
    else
        printf 'cloning: %s\n' "$REPOSITORY_NAME"
        set -- --recurse-submodules
        if [ "$REPOSITORY_NAME" = CPSTL ]; then
            set -- "$@" --branch main
        fi
        # Optional .rev indexes can fail to rename in synced folders. Keep this
        # setting command-scoped, including recursive submodule clones.
        if ! git -c pack.writeReverseIndex=false clone "$@" "$REPOSITORY_ORIGIN" "$REPOSITORY_PATH"; then
            printf 'error: clone failed for %s\n' "$REPOSITORY_NAME" >&2
            FAILED=1
        fi
    fi
done < "$MANIFEST"

if [ "$FAILED" -ne 0 ]; then
    fail "workspace setup completed with errors"
fi

printf 'Workspace setup complete. CPSTL tracks origin/main; other existing repositories were not updated.\n'

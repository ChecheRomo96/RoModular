#!/bin/sh

set -eu

SCRIPT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
ROMODULAR_ROOT=$(CDPATH= cd -- "$SCRIPT_DIR/.." && pwd)
MANIFEST="$ROMODULAR_ROOT/.romodular/workspace/repositories.txt"

# Runtime libraries in dependency order. MIDILAR is legacy and opt-in.
LIBRARIES="Foundation DspCore MCC"
LEGACY_LIBRARIES="MIDILAR"

LIBRARIES_ROOT=
INCLUDE_LEGACY=0
FORCE=0
DRY_RUN=0

usage() {
    printf '%s\n' \
        "Usage: $0 <arduino-libraries-path> [--include-legacy] [--force] [--dry-run]" \
        "" \
        "Clone the RoModular Arduino libraries into an Arduino libraries folder." \
        "" \
        "Options:" \
        "  --include-legacy   Also install MIDILAR (legacy, pending reconstruction)." \
        "  --force            Replace existing library folders that are not the expected clone." \
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
        --include-legacy) INCLUDE_LEGACY=1; shift ;;
        --force) FORCE=1; shift ;;
        --dry-run) DRY_RUN=1; shift ;;
        -h|--help) usage; exit 0 ;;
        -*) fail "unknown argument: $1" ;;
        *)
            [ -z "$LIBRARIES_ROOT" ] || fail "unexpected argument: $1"
            LIBRARIES_ROOT=$1
            shift
            ;;
    esac
done

[ -n "$LIBRARIES_ROOT" ] || { usage >&2; exit 1; }
command -v git >/dev/null 2>&1 || fail "Git is required but was not found on PATH"
[ -f "$MANIFEST" ] || fail "repository manifest not found: $MANIFEST"
[ "$INCLUDE_LEGACY" -eq 0 ] || LIBRARIES="$LIBRARIES $LEGACY_LIBRARIES"

case "$LIBRARIES_ROOT" in
    /*) ;;
    # Windows drive paths from Git Bash, e.g. C:\Users\me.
    [A-Za-z]:*) LIBRARIES_ROOT=$(cygpath -u "$LIBRARIES_ROOT") ;;
    *) LIBRARIES_ROOT=$(pwd)/$LIBRARIES_ROOT ;;
esac

printf 'Arduino libraries: %s\n' "$LIBRARIES_ROOT"
if [ "$DRY_RUN" -eq 0 ]; then
    mkdir -p "$LIBRARIES_ROOT"
fi

FAILED=0
for LIBRARY in $LIBRARIES; do
    ORIGIN=$(tr -d '\r' < "$MANIFEST" | awk -F'|' -v name="$LIBRARY" '$1 == name { print $2 }')
    if [ -z "$ORIGIN" ]; then
        printf 'error: %s is missing from %s\n' "$LIBRARY" "$MANIFEST" >&2
        FAILED=1
        continue
    fi

    LIBRARY_PATH="$LIBRARIES_ROOT/$LIBRARY"

    if [ -e "$LIBRARY_PATH" ]; then
        ACTUAL_ORIGIN=
        if [ -e "$LIBRARY_PATH/.git" ]; then
            ACTUAL_ORIGIN=$(git -C "$LIBRARY_PATH" remote get-url origin 2>/dev/null || true)
        fi
        if [ -n "$ACTUAL_ORIGIN" ] && \
           [ "$(normalize_git_origin "$ACTUAL_ORIGIN")" = "$(normalize_git_origin "$ORIGIN")" ]; then
            printf 'present: %s (left unchanged)\n' "$LIBRARY"
            continue
        fi
        if [ "$FORCE" -ne 1 ]; then
            printf 'error: %s already exists and is not a clone of %s\n' "$LIBRARY_PATH" "$ORIGIN" >&2
            printf '       rerun with --force to replace it\n' >&2
            FAILED=1
            continue
        fi
        if [ "$DRY_RUN" -eq 1 ]; then
            printf '[dry-run] replace %s\n' "$LIBRARY_PATH"
            continue
        fi
        rm -rf -- "$LIBRARY_PATH"
    elif [ "$DRY_RUN" -eq 1 ]; then
        printf '[dry-run] clone %s into %s\n' "$ORIGIN" "$LIBRARY_PATH"
        continue
    fi

    printf 'cloning: %s\n' "$LIBRARY"
    if ! git clone "$ORIGIN" "$LIBRARY_PATH"; then
        printf 'error: clone failed for %s\n' "$LIBRARY" >&2
        FAILED=1
    fi
done

[ "$FAILED" -eq 0 ] || fail "Arduino library installation completed with errors"
printf 'Arduino libraries installed. Existing clones were not updated.\n'
printf 'DspCore and MCC on Arduino AVR require -std=gnu++17 (see their READMEs).\n'

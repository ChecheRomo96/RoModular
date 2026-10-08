#!/bin/sh

set -eu

SCRIPT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
ROMODULAR_ROOT=$(CDPATH= cd -- "$SCRIPT_DIR/.." && pwd)
MANIFEST="$ROMODULAR_ROOT/.romodular/workspace/repositories.txt"
PINS_MANIFEST="$ROMODULAR_ROOT/.romodular/workspace/release-pins.txt"

# Released Arduino libraries, in dependency order.  DspCore is deliberately
# excluded until it has a release tag; --use-head is the explicit development
# opt-in and includes it.
STABLE_LIBRARIES="CPSTL Foundation MCC MIDILAR"
HEAD_LIBRARIES="CPSTL Foundation DspCore MCC MIDILAR"

LIBRARIES_ROOT=
FORCE=0
DRY_RUN=0
USE_HEAD=0

usage() {
    printf '%s\n' \
        "Usage: $0 <arduino-libraries-path> [--force] [--dry-run] [--use-head]" \
        "" \
        "Clone the RoModular Arduino libraries into an Arduino libraries folder," \
        "or bring existing clones up to date." \
        "" \
        "Options:" \
        "  --force            Replace existing library folders that are not the expected clone." \
        "  --dry-run          Print planned actions without changing the filesystem." \
        "  --use-head         Install development heads instead of the release pins." \
        "  -h, --help         Show this help text." \
        "" \
        "--include-legacy is still accepted and ignored: MIDILAR is always installed."
}

fail() {
    printf 'error: %s\n' "$1" >&2
    exit 1
}

normalize_git_origin() {
    printf '%s' "$1" | sed -e 's#/*$##' -e 's#\.git$##'
}

# Moves a clean clone to an immutable tag, or fast-forwards it to a development
# branch when --use-head is selected.  Local changes are never overwritten.
update_clone() {
    LIBRARY=$1
    LIBRARY_PATH=$2
    REF=$3

    if [ -n "$(git -C "$LIBRARY_PATH" status --porcelain)" ]; then
        printf 'warning: %s has local changes; not updated\n' "$LIBRARY" >&2
        SKIPPED=1
        return 0
    fi
    if [ "$DRY_RUN" -eq 1 ]; then
        printf '[dry-run] update %s to %s\n' "$LIBRARY" "$REF"
        return 0
    fi
    if ! git -C "$LIBRARY_PATH" fetch --quiet --tags origin; then
        printf 'error: fetch failed for %s\n' "$LIBRARY" >&2
        FAILED=1
        return 0
    fi
    if [ "$USE_HEAD" -eq 0 ]; then
        if ! git -C "$LIBRARY_PATH" rev-parse --verify --quiet "refs/tags/$REF^{commit}" >/dev/null; then
            printf 'error: tag %s was not found for %s\n' "$REF" "$LIBRARY" >&2
            FAILED=1
            return 0
        fi
        git -C "$LIBRARY_PATH" checkout --quiet --detach "$REF"
        printf 'pinned: %s (%s at %s)\n' "$LIBRARY" "$REF" "$(git -C "$LIBRARY_PATH" rev-parse --short HEAD)"
    else
        if ! git -C "$LIBRARY_PATH" checkout --quiet "$REF" 2>/dev/null &&
           ! git -C "$LIBRARY_PATH" checkout --quiet -b "$REF" --track "origin/$REF"; then
            printf 'error: cannot switch %s to branch %s\n' "$LIBRARY" "$REF" >&2
            FAILED=1
            return 0
        fi
        if ! git -C "$LIBRARY_PATH" merge --quiet --ff-only "origin/$REF"; then
            printf 'warning: %s has commits not on origin/%s; not updated\n' "$LIBRARY" "$REF" >&2
            SKIPPED=1
            return 0
        fi
        printf 'updated: %s (%s at %s)\n' "$LIBRARY" "$REF" "$(git -C "$LIBRARY_PATH" rev-parse --short HEAD)"
    fi
}

while [ "$#" -gt 0 ]; do
    case "$1" in
        --include-legacy) shift ;;
        --force) FORCE=1; shift ;;
        --dry-run) DRY_RUN=1; shift ;;
        --use-head) USE_HEAD=1; shift ;;
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
[ -f "$PINS_MANIFEST" ] || fail "release pins manifest not found: $PINS_MANIFEST"

if [ "$USE_HEAD" -eq 0 ]; then
    LIBRARIES=$STABLE_LIBRARIES
    MODE_NOTE="release pins"
else
    LIBRARIES=$HEAD_LIBRARIES
    MODE_NOTE="development heads"
fi

case "$LIBRARIES_ROOT" in
    /*) ;;
    # Windows drive paths from Git Bash, e.g. C:\Users\me.
    [A-Za-z]:*) LIBRARIES_ROOT=$(cygpath -u "$LIBRARIES_ROOT") ;;
    *) LIBRARIES_ROOT=$(pwd)/$LIBRARIES_ROOT ;;
esac

printf 'Arduino libraries: %s (%s)\n' "$LIBRARIES_ROOT" "$MODE_NOTE"
if [ "$DRY_RUN" -eq 0 ]; then
    mkdir -p "$LIBRARIES_ROOT"
fi

FAILED=0
SKIPPED=0
for LIBRARY in $LIBRARIES; do
    ORIGIN=$(tr -d '\r' < "$MANIFEST" | awk -F'|' -v name="$LIBRARY" '$1 == name { print $2 }')
    if [ -z "$ORIGIN" ]; then
        printf 'error: %s is missing from %s\n' "$LIBRARY" "$MANIFEST" >&2
        FAILED=1
        continue
    fi

    LIBRARY_PATH="$LIBRARIES_ROOT/$LIBRARY"
    if [ "$USE_HEAD" -eq 0 ]; then
        REF=$(tr -d '\r' < "$PINS_MANIFEST" | awk -F'|' -v name="$LIBRARY" '$1 == name { print $2 }')
        [ -n "$REF" ] || { printf 'error: %s is missing from %s\n' "$LIBRARY" "$PINS_MANIFEST" >&2; FAILED=1; continue; }
    else
        REF=main
    fi

    if [ -e "$LIBRARY_PATH" ]; then
        ACTUAL_ORIGIN=
        if [ -e "$LIBRARY_PATH/.git" ]; then
            ACTUAL_ORIGIN=$(git -C "$LIBRARY_PATH" remote get-url origin 2>/dev/null || true)
        fi
        if [ -n "$ACTUAL_ORIGIN" ] && \
           [ "$(normalize_git_origin "$ACTUAL_ORIGIN")" = "$(normalize_git_origin "$ORIGIN")" ]; then
            update_clone "$LIBRARY" "$LIBRARY_PATH" "$REF"
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
        printf '[dry-run] clone %s (%s) into %s\n' "$ORIGIN" "$REF" "$LIBRARY_PATH"
        continue
    fi

    printf 'cloning: %s (%s)\n' "$LIBRARY" "$REF"
    if ! git clone --branch "$REF" "$ORIGIN" "$LIBRARY_PATH"; then
        printf 'error: clone failed for %s\n' "$LIBRARY" >&2
        FAILED=1
    fi
done

[ "$FAILED" -eq 0 ] || fail "Arduino library installation completed with errors"
if [ "$SKIPPED" -eq 0 ]; then
    printf 'Arduino libraries installed and at the requested references.\n'
else
    printf 'Arduino libraries installed; the clones warned about above were not updated.\n'
fi
printf 'DspCore, MCC and MIDILAR on Arduino AVR require -std=gnu++17 (see their READMEs).\n'

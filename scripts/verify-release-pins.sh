#!/bin/sh

# Verify that an installed Arduino-library set exactly matches the workspace
# release manifest and that every declared Arduino dependency is satisfied by
# the same set.  This keeps installer pins, library metadata and CI aligned.
set -eu

SCRIPT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
ROMODULAR_ROOT=$(CDPATH= cd -- "$SCRIPT_DIR/.." && pwd)
PINS_MANIFEST="$ROMODULAR_ROOT/.romodular/workspace/release-pins.txt"

usage() {
    printf '%s\n' "Usage: $0 <arduino-libraries-path>"
}

fail() {
    printf 'error: %s\n' "$1" >&2
    exit 1
}

version_at_least() {
    awk -v actual="$1" -v required="$2" '
        BEGIN {
            split(actual, a, "."); split(required, r, ".");
            for (i = 1; i <= 3; ++i) {
                if ((a[i] + 0) > (r[i] + 0)) exit 0;
                if ((a[i] + 0) < (r[i] + 0)) exit 1;
            }
            exit 0;
        }'
}

[ "$#" -eq 1 ] || { usage >&2; exit 1; }
LIBRARIES_ROOT=$1
[ -d "$LIBRARIES_ROOT" ] || fail "library directory not found: $LIBRARIES_ROOT"
[ -f "$PINS_MANIFEST" ] || fail "release pins manifest not found: $PINS_MANIFEST"

while IFS='|' read -r LIBRARY PIN; do
    case "$LIBRARY" in ''|'#'*) continue ;; esac
    LIBRARY_PATH="$LIBRARIES_ROOT/$LIBRARY"
    PROPERTIES="$LIBRARY_PATH/library.properties"
    [ -f "$PROPERTIES" ] || fail "$LIBRARY is missing library.properties"
    [ -e "$LIBRARY_PATH/.git" ] || fail "$LIBRARY is not a Git checkout"

    ACTUAL_TAG=$(git -C "$LIBRARY_PATH" describe --exact-match --tags 2>/dev/null || true)
    [ "$ACTUAL_TAG" = "$PIN" ] || fail "$LIBRARY is at '${ACTUAL_TAG:-untagged}' instead of $PIN"

    VERSION=$(awk -F= '$1 == "version" { print $2; exit }' "$PROPERTIES")
    [ "$VERSION" = "${PIN#v}" ] || fail "$LIBRARY metadata is $VERSION but pin is $PIN"

    DEPENDS=$(awk -F= '$1 == "depends" { print $2; exit }' "$PROPERTIES")
    printf '%s' "$DEPENDS" | tr ',' '\n' | while IFS= read -r DEPENDENCY; do
        DEPENDENCY=$(printf '%s' "$DEPENDENCY" | sed 's/^ *//;s/ *$//')
        [ -n "$DEPENDENCY" ] || continue
        NAME=$(printf '%s' "$DEPENDENCY" | sed 's/ *(.*//')
        REQUIRED=$(printf '%s' "$DEPENDENCY" | sed -n 's/.*(>=[ ]*\([0-9][0-9.]*\)).*/\1/p')
        [ -n "$REQUIRED" ] || continue
        DEPENDENCY_VERSION=$(awk -F= '$1 == "version" { print $2; exit }' "$LIBRARIES_ROOT/$NAME/library.properties" 2>/dev/null || true)
        [ -n "$DEPENDENCY_VERSION" ] || fail "$LIBRARY requires $NAME but it is not installed"
        version_at_least "$DEPENDENCY_VERSION" "$REQUIRED" ||
            fail "$LIBRARY requires $NAME >=$REQUIRED but installed version is $DEPENDENCY_VERSION"
    done
done < "$PINS_MANIFEST"

printf '%s\n' "Release pins and declared Arduino requirements are compatible."

#!/bin/sh
# Builds dist/SugarDaddy-<version>.zip with only what WoW loads,
# inside a SugarDaddy/ folder so the .toc name matches.
set -eu

NAME=SugarDaddy
cd "$(dirname "$0")"

VERSION=$(sed -n 's/^## Version: *//p' "$NAME.toc" | tr -d '\r')
[ -n "$VERSION" ] || { echo "No ## Version in $NAME.toc" >&2; exit 1; }

STAGE=$(mktemp -d)
trap 'rm -rf "$STAGE"' EXIT
OUT="$STAGE/$NAME"
mkdir -p "$OUT"

copy() {
    [ -f "$1" ] || { echo "Missing file: $1" >&2; exit 1; }
    mkdir -p "$OUT/$(dirname "$1")"
    cp "$1" "$OUT/$1"
}

copy "$NAME.toc"
copy LICENSE
copy media/icon.tga

# Every file the .toc loads (skips ## lines, comments and blanks).
grep -v -e '^#' -e '^[[:space:]]*$' "$NAME.toc" | tr -d '\r' | tr '\\' '/' | while read -r file; do
    copy "$file"
done

mkdir -p dist
ZIP="$PWD/dist/$NAME-$VERSION.zip"
rm -f "$ZIP"
(cd "$STAGE" && zip -rqX "$ZIP" "$NAME")

echo "Built $ZIP"
unzip -l "$ZIP"

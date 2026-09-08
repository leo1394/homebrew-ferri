#!/bin/bash
set -euo pipefail

REPOSITORY="${FERRIE_REPOSITORY:-leo1394/homebrew-ferrie}"
INSTALL_DIR="${FERRIE_INSTALL_DIR:-$HOME/.local/bin}"
DATA_DIR="${FERRIE_DATA_DIR:-$HOME/.local/share}"
VERSION="${1:-${FERRIE_VERSION:-}}"
SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
TEMP_DIR=""
STAGED_FILE=""
cleanup() {
    [ -z "$TEMP_DIR" ] || rm -rf "$TEMP_DIR"
    [ -z "$STAGED_FILE" ] || rm -f "$STAGED_FILE"
}
trap cleanup EXIT
trap 'exit 130' INT
trap 'exit 143' TERM
fail() { printf 'ferrie installer: %s\n' "$1" >&2; exit 1; }
case "$INSTALL_DIR" in /*) ;; *) fail 'FERRIE_INSTALL_DIR must be absolute' ;; esac
case "$DATA_DIR" in /*) ;; *) fail 'FERRIE_DATA_DIR must be absolute' ;; esac
TEMP_DIR="$(mktemp -d "${TMPDIR:-/tmp}/ferrie-install.XXXXXX")"
if [ "$VERSION" = '--local' ]; then
    [ -x "$SCRIPT_DIR/bin/ferrie" ] || fail 'Build first: go build -o bin/ferrie .'
    cp "$SCRIPT_DIR/bin/ferrie" "$TEMP_DIR/ferrie"
else
    command -v curl >/dev/null || fail 'curl is required'
    case "$(uname -s)" in
        Darwin) PLATFORM=darwin ;;
        Linux) PLATFORM=linux ;;
        *) fail 'No prebuilt Ferrie for this Unix; build from source and use --local' ;;
    esac
    case "$(uname -m)" in
        arm64|aarch64) ARCH=arm64 ;;
        x86_64|amd64) ARCH=amd64 ;;
        *) fail 'Supported architectures: arm64 and amd64' ;;
    esac
    if [ -z "$VERSION" ]; then
        VERSION="$(curl -fsSL --retry 3 "https://raw.githubusercontent.com/$REPOSITORY/master/VERSION.txt")"
    fi
    VERSION="${VERSION#v}"
    [[ "$VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] || fail 'Expected a version such as 0.1.0'
    ASSET="ferrie_${VERSION}_${PLATFORM}_${ARCH}"
    BASE="https://github.com/$REPOSITORY/releases/download/v$VERSION"
    curl -fsSL --retry 3 "$BASE/$ASSET" -o "$TEMP_DIR/ferrie"
    curl -fsSL --retry 3 "$BASE/SHA256SUMS" -o "$TEMP_DIR/SHA256SUMS"
    EXPECTED="$(awk -v name="$ASSET" '$2 == name {print $1}' "$TEMP_DIR/SHA256SUMS")"
    [[ "$EXPECTED" =~ ^[0-9a-f]{64}$ ]] || fail 'Missing release checksum'
    if command -v shasum >/dev/null; then
        ACTUAL="$(shasum -a 256 "$TEMP_DIR/ferrie" | awk '{print $1}')"
    elif command -v sha256sum >/dev/null; then
        ACTUAL="$(sha256sum "$TEMP_DIR/ferrie" | awk '{print $1}')"
    else
        fail 'shasum or sha256sum is required'
    fi
    [ "$ACTUAL" = "$EXPECTED" ] || fail 'SHA256 verification failed'
    chmod 0755 "$TEMP_DIR/ferrie"
    REPORTED="$("$TEMP_DIR/ferrie" --version)"
    VERSION_LINE="${REPORTED%%$'\n'*}"
    [[ "$VERSION_LINE" =~ ^ferrie\ version\ ([0-9]+\.[0-9]+\.[0-9]+)\ \([0-9]{4}-[0-9]{2}-[0-9]{2}\)$ ]] || fail 'Invalid version output'
    [ "${BASH_REMATCH[1]}" = "$VERSION" ] || fail 'Version mismatch'
fi
mkdir -p "$INSTALL_DIR" "$DATA_DIR/bash-completion/completions" "$DATA_DIR/zsh/site-functions" "$DATA_DIR/fish/vendor_completions.d"
for shell in bash zsh fish; do
    "$TEMP_DIR/ferrie" __completion "$shell" > "$TEMP_DIR/$shell"
done
# Older releases do not include the embedded manual yet.
if "$TEMP_DIR/ferrie" __man > "$TEMP_DIR/ferrie.1" 2>/dev/null; then
    mkdir -p "$DATA_DIR/man/man1"
    cp "$TEMP_DIR/ferrie.1" "$DATA_DIR/man/man1/ferrie.1"
    printf 'Manual: %s/man/man1/ferrie.1\n' "$DATA_DIR"
    printf 'If man ferrie cannot find it, run: export MANPATH="%s/man:${MANPATH:-}"\n' "$DATA_DIR"
fi
STAGED_FILE="$(mktemp "$INSTALL_DIR/.ferrie.XXXXXX")"
cp "$TEMP_DIR/ferrie" "$STAGED_FILE"
chmod 0755 "$STAGED_FILE"
mv -f "$STAGED_FILE" "$INSTALL_DIR/ferrie"
STAGED_FILE=""
cp "$TEMP_DIR/bash" "$DATA_DIR/bash-completion/completions/ferrie"
cp "$TEMP_DIR/zsh" "$DATA_DIR/zsh/site-functions/_ferrie"
cp "$TEMP_DIR/fish" "$DATA_DIR/fish/vendor_completions.d/ferrie.fish"
printf 'Installed %s\n' "$("$INSTALL_DIR/ferrie" --version)"
printf 'Executable: %s/ferrie\nCompletion data: %s\n' "$INSTALL_DIR" "$DATA_DIR"
printf 'Add the executable directory to PATH. See README.md for shell completion activation.\n'

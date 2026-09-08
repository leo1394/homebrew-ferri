#!/bin/bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
TEMP="$(mktemp -d)"
trap 'rm -rf "$TEMP"' EXIT
export FERRIE_INSTALL_DIR="$TEMP/bin space"
export FERRIE_DATA_DIR="$TEMP/share space"
export FERRIE_TEST_FIXTURES="$TEMP/releases"
mkdir -p "$FERRIE_TEST_FIXTURES" "$TEMP/tools"
case "$(uname -s)" in Darwin) platform=darwin ;; Linux) platform=linux ;; *) exit 0 ;; esac
case "$(uname -m)" in arm64|aarch64) arch=arm64 ;; *) arch=amd64 ;; esac
version="$(cat "$ROOT/VERSION.txt")"
expected_output="$("$ROOT/bin/ferrie" --version)"
asset="ferrie_${version}_${platform}_${arch}"
cp "$ROOT/bin/ferrie" "$FERRIE_TEST_FIXTURES/$asset"
printf '%s\n' "$version" > "$FERRIE_TEST_FIXTURES/VERSION.txt"
if command -v shasum >/dev/null; then
    digest="$(shasum -a 256 "$ROOT/bin/ferrie" | awk '{print $1}')"
else
    digest="$(sha256sum "$ROOT/bin/ferrie" | awk '{print $1}')"
fi
printf '%s  %s\n' "$digest" "$asset" > "$FERRIE_TEST_FIXTURES/SHA256SUMS"
cat > "$TEMP/tools/curl" <<'CURL'
#!/bin/bash
set -euo pipefail
output=''
url=''
while [ "$#" -gt 0 ]; do
    case "$1" in
        -o) output="$2"; shift 2 ;;
        --retry) shift 2 ;;
        https://*) url="$1"; shift ;;
        *) shift ;;
    esac
done
file="$FERRIE_TEST_FIXTURES/${url##*/}"
if [ -n "$output" ]; then cp "$file" "$output"; else cat "$file"; fi
CURL
chmod +x "$TEMP/tools/curl"
export PATH="$TEMP/tools:$PATH"
bash "$ROOT/install.sh"
[[ "$("$FERRIE_INSTALL_DIR/ferrie" --version)" == "$expected_output" ]]
[[ -f "$FERRIE_DATA_DIR/zsh/site-functions/_ferrie" ]]
"$ROOT/bin/ferrie" __man > "$TEMP/expected.1"
cmp "$TEMP/expected.1" "$FERRIE_DATA_DIR/man/man1/ferrie.1"
printf '%064d  %s\n' 0 "$asset" > "$FERRIE_TEST_FIXTURES/SHA256SUMS"
if bash "$ROOT/install.sh" "$version" > "$TEMP/output" 2>&1; then
    printf 'Installer accepted wrong checksum\n' >&2
    exit 1
fi
[[ "$("$FERRIE_INSTALL_DIR/ferrie" --version)" == "$expected_output" ]]
if bash "$ROOT/install.sh" '../bad' > "$TEMP/output" 2>&1; then exit 1; fi
printf 'Remote installer checksum, version and space-path tests passed\n'

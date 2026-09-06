#!/bin/bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
TEMP="$(mktemp -d)"
trap 'rm -rf "$TEMP"' EXIT
cd "$TEMP"
touch 'app with spaces.apk'
mkdir 'package directory'
"$ROOT/bin/ferri" __completion bash > "$TEMP/ferri.bash"
source "$TEMP/ferri.bash"
COMP_WORDS=(ferri --tar)
COMP_CWORD=1
_ferri
[[ "${COMPREPLY[*]}" == '--target' ]]
COMP_WORDS=(ferri --target 'app w')
COMP_CWORD=2
_ferri
[[ "${#COMPREPLY[@]}" == 1 && "${COMPREPLY[0]}" == 'app with spaces.apk' ]]
COMP_WORDS=(ferri --target 'package')
_ferri
[[ "${COMPREPLY[0]}" == 'package directory' ]]
# The fixture avoids starting adb while checking device completion.
ferri() { printf 'serial-1\nserial-2\n'; }
COMP_WORDS=(ferri --device serial-2)
_ferri
[[ "${COMPREPLY[*]}" == 'serial-2' ]]
COMP_WORDS=(ferri --ur)
COMP_CWORD=1
_ferri
[[ "${COMPREPLY[*]}" == '--url' ]]
COMP_WORDS=(ferri --and)
_ferri
[[ "${COMPREPLY[*]}" == '--android' ]]
COMP_WORDS=(ferri --url 'app')
COMP_CWORD=2
_ferri
[[ "${#COMPREPLY[@]}" == 0 ]]
printf 'Bash completion tests passed\n'

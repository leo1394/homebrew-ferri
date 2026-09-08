#!/bin/bash
# Reproduce checkout's peeled local tag and exercise the actual workflow validator.
set -euo pipefail
root=$(cd "$(dirname "$0")/.." && pwd -P)
scratch=$(mktemp -d)
trap 'rm -rf "$scratch"' EXIT
awk '/          fail\(\)/ { active=1; print "set -euo pipefail" } active && /^      - name:/ { exit } active { sub(/^          /, ""); print }' "$root/.github/workflows/release.yml" > "$scratch/validate.sh"
git init -q --bare "$scratch/remote.git"
git init -q "$scratch/source"
cd "$scratch/source"
git config user.name test
git config user.email test@example.invalid
printf '0.1.0\n' > VERSION.txt
git add VERSION.txt
git commit -qm initial
git tag -a v0.1.0 -m release
git remote add origin "$scratch/remote.git"
git push -q origin HEAD refs/tags/v0.1.0
git clone -q "$scratch/remote.git" "$scratch/checkout"
cd "$scratch/checkout"
source=$(git rev-parse HEAD)
git fetch -q --no-tags origin "+$source:refs/tags/v0.1.0"
[[ "$(git cat-file -t refs/tags/v0.1.0)" == commit ]]
export RELEASE_TAG=v0.1.0 GITHUB_OUTPUT="$scratch/output"
bash "$scratch/validate.sh"
[[ "$(cat "$GITHUB_OUTPUT")" == "source=$source" ]]
expect_failure() {
    if bash "$scratch/validate.sh" > "$scratch/error" 2>&1; then
        echo "Expected validation failure" >&2; exit 1
    fi
    grep -q "$1" "$scratch/error"
}
RELEASE_TAG=master expect_failure 'Invalid release tag'
printf '0.2.0\n' > VERSION.txt
expect_failure 'Tag does not match VERSION.txt'
git restore VERSION.txt
# A different checked-out commit must fail, even with the right version.
git -c user.name=test -c user.email=test@example.invalid commit -qm different --allow-empty
expect_failure 'Remote tag does not match checked-out source'
git checkout -q "$source"
# A genuinely lightweight remote tag is still rejected.
git -C "$scratch/source" tag -d v0.1.0 >/dev/null
git -C "$scratch/source" tag v0.1.0
git -C "$scratch/source" push -q --force origin refs/tags/v0.1.0
expect_failure 'Remote release tag must be annotated'
# Exercise the same source-change guard used before committing the bottle Formula.
awk '/          while IFS= read -r path/ { active=1 } active { sub(/^          /, ""); print } active && /done <<< / { exit }' "$root/.github/workflows/release.yml" > "$scratch/guard.sh"
export changes
changes=$(printf '%s\n' .gitignore .idea/.gitignore .idea/misc.xml README.md README-EN.md .github/workflows/release.yml RELEASING.md tests/release_tag_test.sh Formula/ferrie.rb scripts/merge-bottles.rb tests/bottle_metadata_test.rb)
bash "$scratch/guard.sh"
for changes in main.go go.mod go.sum VERSION.txt completions/ferrie.bash scripts/release/main.go scripts/release-bottles.sh; do
    if bash "$scratch/guard.sh" > "$scratch/error" 2>&1; then
        echo "Unexpectedly accepted changed source: $changes" >&2; exit 1
    fi
    grep -q 'Source changed since release' "$scratch/error"
done
echo 'release tag and source guard tests passed'

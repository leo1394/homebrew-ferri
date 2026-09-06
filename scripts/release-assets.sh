#!/bin/bash
# Upload immutable release files; safe to resume a partially completed upload.
set -euo pipefail
: "${GITHUB_REPOSITORY:?}"
: "${GITHUB_REF_NAME:?}"
[[ "$GITHUB_REF_NAME" =~ ^v[0-9]+\.[0-9]+\.[0-9]+$ ]]
if ! gh release view "$GITHUB_REF_NAME" --repo "$GITHUB_REPOSITORY" >/dev/null 2>&1; then
    gh release create "$GITHUB_REF_NAME" --repo "$GITHUB_REPOSITORY" --verify-tag --generate-notes
fi
check_dir=$(mktemp -d)
trap 'rm -rf "$check_dir"' EXIT
for asset in "$@"; do
    name=$(basename "$asset")
    rm -f "$check_dir/$name"
    if gh release download "$GITHUB_REF_NAME" --repo "$GITHUB_REPOSITORY" --pattern "$name" --dir "$check_dir" >/dev/null 2>&1; then
        cmp "$asset" "$check_dir/$name" || { echo "Refusing to overwrite changed release asset: $name" >&2; exit 1; }
    else
        # No --clobber: a race or network error must never replace an existing asset.
        gh release upload "$GITHUB_REF_NAME" "$asset" --repo "$GITHUB_REPOSITORY"
    fi
 done

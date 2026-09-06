#!/bin/bash
set -euo pipefail
: "${GITHUB_REPOSITORY:?}"
: "${GITHUB_REF_NAME:?}"
[[ "$GITHUB_REF_NAME" =~ ^v[0-9]+\.[0-9]+\.[0-9]+$ ]]
repo_root=$(cd "$(dirname "$0")/.." && pwd -P)
version=$(cat "$repo_root/VERSION.txt")
[[ "$GITHUB_REF_NAME" == "v$version" ]]
owner=${GITHUB_REPOSITORY%/*}
repository=${GITHUB_REPOSITORY##*/}
tap="$owner/${repository#homebrew-}"
output_dir="$repo_root/bottle-output"
mkdir -p "$output_dir"
case "${1:-}" in
    build)
        brew tap-new --no-git "$tap"
        cp "$repo_root/Formula/ferri.rb" "$(brew --repository "$tap")/Formula/ferri.rb"
        if brew commands | grep -qx trust; then brew trust --formula "$tap/ferri"; fi
        brew install --build-bottle "$tap/ferri"
        brew test "$tap/ferri"
        cd "$output_dir"
        brew bottle --json --root-url "https://github.com/$GITHUB_REPOSITORY/releases/download/$GITHUB_REF_NAME" "$tap/ferri"
        # Prove this artifact can be poured, including its completion files.
        brew uninstall "$tap/ferri"
        ruby -rjson -rfileutils - "$(brew --repository "$tap")/Formula/ferri.rb" <<'RUBY'
metadata = JSON.parse(File.read(Dir["*.bottle.json"].fetch(0))).values.fetch(0).fetch("bottle")
block = "\n  bottle do\n    root_url #{("file://" + Dir.pwd).dump}\n"
metadata.fetch("tags").each do |tag, entry|
  FileUtils.cp(entry.fetch("local_filename"), entry.fetch("filename"))
  cellar = entry["cellar"] || metadata.fetch("cellar")
  cellar = %w[any any_skip_relocation].include?(cellar) ? ":#{cellar}" : cellar.dump
  block += "    sha256 cellar: #{cellar}, #{tag}: #{entry.fetch("sha256").dump}\n"
end
block += "  end\n"
path = ARGV.fetch(0)
text = File.read(path).sub(/\n  bottle do\n.*?^  end\n/m, "")
File.write(path, text.sub("  license \"MIT\"\n", "  license \"MIT\"\n#{block}"))
RUBY
        brew install --force-bottle "$tap/ferri"
        # Keep only the original brew bottle artifacts for the publishing job.
        rm -f ferri-[0-9]*.bottle.tar.gz
        brew test "$tap/ferri"
        ;;
    publish)
        ruby "$repo_root/scripts/merge-bottles.rb" "$repo_root" "$output_dir" "$GITHUB_REPOSITORY" "$version"
        bash "$repo_root/scripts/release-assets.sh" "$output_dir"/upload/*.bottle.tar.gz
        ;;
    *) echo 'Usage: release-bottles.sh build|publish' >&2; exit 2 ;;
esac

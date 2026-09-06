# Validate CI bottle metadata and write only the bottle stanza into the Formula.
require "json"
require "digest"
require "fileutils"

root, directory, repository, version = ARGV
abort "invalid repository/version" unless repository&.match?(%r{\A[A-Za-z0-9_.-]+/homebrew-ferri\z}) && version&.match?(/\A\d+\.\d+\.\d+\z/)
url = "https://github.com/#{repository}/releases/download/v#{version}"
tags = {}
files = Dir[File.join(directory, "*.bottle.json")]
abort "expected two bottle metadata files" unless files.length == 2
upload = File.join(directory, "upload")
FileUtils.rm_rf(upload)
FileUtils.mkdir_p(upload)
files.each do |file|
  contents = JSON.parse(File.read(file))
  abort "unexpected formula count" unless contents.length == 1
  data = contents.values.first
  formula, bottle = data.fetch("formula"), data.fetch("bottle")
  abort "wrong formula/version" unless formula["name"] == "ferri" && formula["pkg_version"] == version
  abort "wrong bottle URL/rebuild" unless bottle["root_url"] == url && bottle["rebuild"] == 0
  abort "expected one platform per bottle" unless bottle.fetch("tags").length == 1
  bottle.fetch("tags").each do |tag, details|
    abort "unexpected or duplicate platform" unless %w[arm64_sequoia sequoia].include?(tag) && !tags.key?(tag)
    cellar = details["cellar"] || bottle["cellar"]
    abort "bottle is not relocatable" unless %w[any any_skip_relocation].include?(cellar)
    local_name = "ferri--#{version}.#{tag}.bottle.tar.gz"
    remote_name = "ferri-#{version}.#{tag}.bottle.tar.gz"
    abort "unexpected filename" unless details["local_filename"] == local_name && details["filename"] == remote_name
    archive = File.join(directory, local_name)
    sha = details.fetch("sha256")
    abort "bottle checksum mismatch" unless sha.match?(/\A[0-9a-f]{64}\z/) && Digest::SHA256.file(archive).hexdigest == sha
    FileUtils.cp(archive, File.join(upload, remote_name))
    tags[tag] = "    sha256 cellar: :#{cellar}, #{tag}: \"#{sha}\""
  end
end
abort "missing macOS architecture" unless tags.keys.sort == %w[arm64_sequoia sequoia]
path = File.join(root, "Formula/ferri.rb")
text = File.read(path)
abort "wrong Formula version" unless text.include?("  version \"#{version}\"")
text = text.sub(/\n  bottle do\n.*?^  end\n/m, "")
block = "\n  bottle do\n    root_url \"#{url}\"\n#{tags.sort.map(&:last).join("\n")}\n  end\n"
abort "missing Formula license" unless text.include?("  license \"MIT\"\n")
text = text.sub("  license \"MIT\"\n", "  license \"MIT\"\n#{block}")
File.write(path, text)

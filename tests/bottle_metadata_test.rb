require "tmpdir"
require "fileutils"
require "json"
require "digest"
require "open3"

script = File.expand_path("../scripts/merge-bottles.rb", __dir__)
Dir.mktmpdir("ferrie-bottle-test") do |directory|
  root = File.join(directory, "repo")
  bottles = File.join(directory, "bottles")
  FileUtils.mkdir_p([File.join(root, "Formula"), bottles])
  original = "class Ferrie < Formula\n  version \"0.1.0\"\n  license \"MIT\"\nend\n"
  formula_path = File.join(root, "Formula/ferrie.rb")
  File.write(formula_path, original)
  %w[arm64_sequoia sequoia].each do |tag|
    local_name = "ferrie--0.1.0.#{tag}.bottle.tar.gz"
    data = "fixture bottle #{tag}"
    File.write(File.join(bottles, local_name), data)
    metadata = { "example/ferrie/ferrie" => {
      "formula" => { "name" => "ferrie", "pkg_version" => "0.1.0" },
      "bottle" => {
        "root_url" => "https://github.com/example/homebrew-ferrie/releases/download/v0.1.0",
        "rebuild" => 0, "cellar" => "any_skip_relocation",
        "tags" => { tag => { "local_filename" => local_name,
          "filename" => local_name.sub("--", "-"), "sha256" => Digest::SHA256.hexdigest(data) } }
      }
    } }
    File.write(File.join(bottles, "#{tag}.bottle.json"), JSON.generate(metadata))
  end
  args = [RbConfig.ruby, script, root, bottles, "example/homebrew-ferrie", "0.1.0"]
  output, status = Open3.capture2e(*args)
  abort output unless status.success?
  result = File.read(formula_path)
  abort "missing bottle architecture" unless result.include?("arm64_sequoia:") && result.include?(" sequoia:")
  digest_columns = result.lines.grep(/sha256 cellar:/).map { |line| line.index('"') }
  abort "misaligned bottle digests" unless digest_columns.uniq.length == 1
  abort "wrong uploaded filename" unless File.file?(File.join(bottles, "upload/ferrie-0.1.0.sequoia.bottle.tar.gz"))
  output, status = Open3.capture2e(*args)
  abort "not idempotent: #{output}" unless status.success? && result == File.read(formula_path)
  File.write(File.join(bottles, "ferrie--0.1.0.sequoia.bottle.tar.gz"), "tampered")
  _, status = Open3.capture2e(*args)
  abort "accepted tampered bottle" if status.success?
  abort "changed Formula on checksum failure" unless result == File.read(formula_path)
end
puts "Bottle metadata and integrity tests passed"

class Ferrie < Formula
  desc "Install Android and iOS apps from files or URLs"
  homepage "https://github.com/leo1394/homebrew-ferrie"
  version "0.2.1"
  license "MIT"

  bottle do
    root_url "https://github.com/leo1394/homebrew-ferrie/releases/download/v0.2.1"
    sha256 cellar: :any_skip_relocation, arm64_sequoia: "a490f9380375ca71bf356ad33260557209d6298f8c2591acfca1b55e540d3edc"
    sha256 cellar: :any_skip_relocation, sequoia:       "cecb25ef2ff0c517837a607ebc90a3f1580394b3b074c475c3e33d7c00427a4b"
  end

  head do
    url "https://github.com/leo1394/homebrew-ferrie.git", branch: "master"
    depends_on "go" => :build
  end

  on_macos do
    on_arm do
      url "https://github.com/leo1394/homebrew-ferrie/releases/download/v0.2.1/ferrie_0.2.1_darwin_arm64", using: :nounzip
      sha256 "ac7fc026237248b41a90e6a0604c95741918f4d0a472656cdd00ced571aa2740"
    end
    on_intel do
      url "https://github.com/leo1394/homebrew-ferrie/releases/download/v0.2.1/ferrie_0.2.1_darwin_amd64", using: :nounzip
      sha256 "66a3e63049d53b400fefbc6d63fa6d3c9a57a430407e78a17f9170291962eb22"
    end
  end

  on_linux do
    on_arm do
      url "https://github.com/leo1394/homebrew-ferrie/releases/download/v0.2.1/ferrie_0.2.1_linux_arm64", using: :nounzip
      sha256 "48922c60588f11b2df72d7db286d923a83df8b63c8ae00312ae222090f1b1fc7"
    end
    on_intel do
      url "https://github.com/leo1394/homebrew-ferrie/releases/download/v0.2.1/ferrie_0.2.1_linux_amd64", using: :nounzip
      sha256 "181700479f803ac0ee7bea3a4b466805b412a2fb3909e08aa74894d988c6e5e7"
    end
  end

  def install
    if build.head?
      system "go", "build", *std_go_args(ldflags: "-s -w"), "."
    else
      bin.install Dir["ferrie_*"][0] => "ferrie"
    end
    chmod 0755, bin/"ferrie"
    generate_completions_from_executable(bin/"ferrie", "__completion")
    man1.mkpath
    (man1/"ferrie.1").write Utils.safe_popen_read(bin/"ferrie", "__man")
    pwsh_completion.mkpath
    (pwsh_completion/"ferrie.ps1").write Utils.safe_popen_read(bin/"ferrie", "__completion", "powershell")
  end

  test do
    output = shell_output("#{bin}/ferrie --version")
    assert_match "ferrie version 0.2.1 (", output
    assert_match(%r{\(\d{4}-\d{2}-\d{2}\)\nhttps://github.com/leo1394/homebrew-ferrie\n\z}, output)
    assert_match "--target", shell_output("#{bin}/ferrie --help")
    assert_match "Did you mean '--target'", shell_output("#{bin}/ferrie --targte app.apk 2>&1", 2)
    assert_match "FERRIE", (man1/"ferrie.1").read
    assert_path_exists bash_completion/"ferrie"
    assert_path_exists zsh_completion/"_ferrie"
    assert_path_exists fish_completion/"ferrie.fish"
    assert_path_exists pwsh_completion/"ferrie.ps1"
  end
end

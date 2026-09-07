class Ferri < Formula
  desc "Install Android and iOS apps from files or URLs"
  homepage "https://github.com/leo1394/homebrew-ferri"
  version "0.1.2"
  license "MIT"

  bottle do
    root_url "https://github.com/leo1394/homebrew-ferri/releases/download/v0.1.2"
    sha256 cellar: :any_skip_relocation, arm64_sequoia: "484bb99288742fc75215f0f716a3b00944858db45ab3878ac7a6dbf862b8e498"
    sha256 cellar: :any_skip_relocation, sequoia:       "35789fcce8a6d44e776adf0d6f44504af4779004bf642e0e1bf71d59b5c7c88a"
  end

  head do
    url "https://github.com/leo1394/homebrew-ferri.git", branch: "master"
    depends_on "go" => :build
  end

  on_macos do
    on_arm do
      url "https://github.com/leo1394/homebrew-ferri/releases/download/v0.1.2/ferri_0.1.2_darwin_arm64", using: :nounzip
      sha256 "14c77d81140a5478ebfb8ef4cc447e309136c78ab410d882ca5a2cf1a3cbd521"
    end
    on_intel do
      url "https://github.com/leo1394/homebrew-ferri/releases/download/v0.1.2/ferri_0.1.2_darwin_amd64", using: :nounzip
      sha256 "b748ee06c389c504f7d3b8fc4086fadb00a0dadf7352d340670144f13d07efae"
    end
  end

  on_linux do
    on_arm do
      url "https://github.com/leo1394/homebrew-ferri/releases/download/v0.1.2/ferri_0.1.2_linux_arm64", using: :nounzip
      sha256 "5b54fb0c15c092b6c3b834f568122315a078779c4c54b8769218299d1710c2e1"
    end
    on_intel do
      url "https://github.com/leo1394/homebrew-ferri/releases/download/v0.1.2/ferri_0.1.2_linux_amd64", using: :nounzip
      sha256 "84e1ad2d115d6e7d3c1153e059bae9e662942fbd9837f1918358bcee231ad747"
    end
  end

  def install
    if build.head?
      system "go", "build", *std_go_args(ldflags: "-s -w"), "."
    else
      bin.install Dir["ferri_*"][0] => "ferri"
    end
    chmod 0755, bin/"ferri"
    generate_completions_from_executable(bin/"ferri", "__completion")
    man1.mkpath
    (man1/"ferri.1").write Utils.safe_popen_read(bin/"ferri", "__man")
    pwsh_completion.mkpath
    (pwsh_completion/"ferri.ps1").write Utils.safe_popen_read(bin/"ferri", "__completion", "powershell")
  end

  test do
    output = shell_output("#{bin}/ferri --version")
    assert_match "ferri version 0.1.2 (", output
    assert_match(%r{\(\d{4}-\d{2}-\d{2}\)\nhttps://github.com/leo1394/homebrew-ferri\n\z}, output)
    assert_match "--target", shell_output("#{bin}/ferri --help")
    assert_match "Did you mean '--target'", shell_output("#{bin}/ferri --targte app.apk 2>&1", 2)
    assert_match "FERRI", (man1/"ferri.1").read
    assert_path_exists bash_completion/"ferri"
    assert_path_exists zsh_completion/"_ferri"
    assert_path_exists fish_completion/"ferri.fish"
    assert_path_exists pwsh_completion/"ferri.ps1"
  end
end

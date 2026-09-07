class Ferri < Formula
  desc "Install Android and iOS apps from files or URLs"
  homepage "https://github.com/leo1394/homebrew-ferri"
  version "0.1.1"
  license "MIT"

  bottle do
    root_url "https://github.com/leo1394/homebrew-ferri/releases/download/v0.1.1"
    sha256 cellar: :any_skip_relocation, arm64_sequoia: "0fc7778f8205a2aa46e84e5fd5695dd7bf3aae9681c1459bbc867a455f0164b7"
    sha256 cellar: :any_skip_relocation, sequoia:       "22084c001066ee4209bb030a56da60cdc0ff2ea8f01d551b4f4e12d4c734706a"
  end

  head do
    url "https://github.com/leo1394/homebrew-ferri.git", branch: "master"
    depends_on "go" => :build
  end

  on_macos do
    on_arm do
      url "https://github.com/leo1394/homebrew-ferri/releases/download/v0.1.1/ferri_0.1.1_darwin_arm64", using: :nounzip
      sha256 "e461df14d8da6448f40bfc2bd904b4dd9b56e0d1fed088d0c1f6669d5d4e6669"
    end
    on_intel do
      url "https://github.com/leo1394/homebrew-ferri/releases/download/v0.1.1/ferri_0.1.1_darwin_amd64", using: :nounzip
      sha256 "e37bc178cbe01b6451dae5f3b3683789d1fd965b7d1e76c7264a2d03ba3c570a"
    end
  end

  on_linux do
    on_arm do
      url "https://github.com/leo1394/homebrew-ferri/releases/download/v0.1.1/ferri_0.1.1_linux_arm64", using: :nounzip
      sha256 "13074fb05e524d7e2f14c7224c1f7f592007c96c55949cec29203ff7f11b5b34"
    end
    on_intel do
      url "https://github.com/leo1394/homebrew-ferri/releases/download/v0.1.1/ferri_0.1.1_linux_amd64", using: :nounzip
      sha256 "8bcffdf1ff28d17adbfdbe57f81a4da9f3d7f3c43777c1afe226c8dea52848dc"
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
    if build.head?
      man1.mkpath
      (man1/"ferri.1").write Utils.safe_popen_read(bin/"ferri", "__man")
    end
    pwsh_completion.mkpath
    (pwsh_completion/"ferri.ps1").write Utils.safe_popen_read(bin/"ferri", "__completion", "powershell")
  end

  test do
    output = shell_output("#{bin}/ferri --version")
    assert_match "ferri version 0.1.1 (", output
    assert_match(%r{\(\d{4}-\d{2}-\d{2}\)\nhttps://github.com/leo1394/homebrew-ferri\n\z}, output)
    assert_match "--target", shell_output("#{bin}/ferri --help")
    assert_match "Did you mean '--target'", shell_output("#{bin}/ferri --targte app.apk 2>&1", 2)
    assert_path_exists bash_completion/"ferri"
    assert_path_exists zsh_completion/"_ferri"
    assert_path_exists fish_completion/"ferri.fish"
    assert_path_exists pwsh_completion/"ferri.ps1"
  end
end

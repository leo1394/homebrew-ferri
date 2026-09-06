class Ferri < Formula
  desc "Install Android and iOS apps from files or URLs"
  homepage "https://github.com/leo1394/homebrew-ferri"
  version "0.1.0"
  license "MIT"

  head do
    url "https://github.com/leo1394/homebrew-ferri.git", branch: "master"
    depends_on "go" => :build
  end

  on_macos do
    on_arm do
      url "https://github.com/leo1394/homebrew-ferri/releases/download/v0.1.0/ferri_0.1.0_darwin_arm64", using: :nounzip
      sha256 "0c3fce86d46209de2297956bbd26d783190dbeeb3e7a3ff44fa64bfe0b0b0f53"
    end
    on_intel do
      url "https://github.com/leo1394/homebrew-ferri/releases/download/v0.1.0/ferri_0.1.0_darwin_amd64", using: :nounzip
      sha256 "47697153a27f2bfd8a8c16486c47cc82b5e837a68323538e8489ab2bde2572ba"
    end
  end

  on_linux do
    on_arm do
      url "https://github.com/leo1394/homebrew-ferri/releases/download/v0.1.0/ferri_0.1.0_linux_arm64", using: :nounzip
      sha256 "14789fd4681c3cdd1206c573830ebf845e57571707dae03fc22342f4829b7d99"
    end
    on_intel do
      url "https://github.com/leo1394/homebrew-ferri/releases/download/v0.1.0/ferri_0.1.0_linux_amd64", using: :nounzip
      sha256 "ef3eff4e0503acc166a9544a6c4f101e4ef182e91affec5d37ba55a448b702a8"
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
    pwsh_completion.mkpath
    (pwsh_completion/"ferri.ps1").write Utils.safe_popen_read(bin/"ferri", "__completion", "powershell")
  end

  test do
    output = shell_output("#{bin}/ferri --version")
    assert_match "ferri version 0.1.0 (", output
    assert_match(%r{\(\d{4}-\d{2}-\d{2}\)\nhttps://github.com/leo1394/homebrew-ferri\n\z}, output)
    assert_match "--target", shell_output("#{bin}/ferri --help")
    assert_match "Did you mean '--target'", shell_output("#{bin}/ferri --targte app.apk 2>&1", 2)
    assert_path_exists bash_completion/"ferri"
    assert_path_exists zsh_completion/"_ferri"
    assert_path_exists fish_completion/"ferri.fish"
    assert_path_exists pwsh_completion/"ferri.ps1"
  end
end

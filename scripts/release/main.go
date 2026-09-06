// Build release assets and write their real SHA256 values into the Homebrew formula.
package main

import (
    "crypto/sha256"
    "fmt"
    "os"
    "os/exec"
    "path/filepath"
    "regexp"
    "strings"
)

func main() {
    if err := build(); err != nil { fmt.Fprintln(os.Stderr, err); os.Exit(1) }
}

func build() error {
    data, err := os.ReadFile("VERSION.txt")
    if err != nil { return err }
    version := strings.TrimSpace(string(data))
    if !regexp.MustCompile(`^\d+\.\d+\.\d+$`).MatchString(version) { return fmt.Errorf("Invalid VERSION.txt") }
    source, err := os.ReadFile("main.go")
    if err != nil { return err }
    if !strings.Contains(string(source), `const version = "` + version + `"`) { return fmt.Errorf("Update main.go version first") }
    if err := os.MkdirAll("dist", 0o755); err != nil { return err }
    checksums := strings.Builder{}
    formula := strings.Builder{}
    fmt.Fprintf(&formula, `class Ferri < Formula
  desc "Install Android and iOS apps from files or URLs"
  homepage "https://github.com/leo1394/homebrew-ferri"
  version "%s"
  license "MIT"

  head do
    url "https://github.com/leo1394/homebrew-ferri.git", branch: "master"
    depends_on "go" => :build
  end

`, version)
    for _, system := range []string{"darwin", "linux", "windows"} {
        if system != "windows" {
            scope := "on_linux"
            if system == "darwin" { scope = "on_macos" }
            fmt.Fprintf(&formula, "  %s do\n", scope)
        }
        for _, arch := range []string{"arm64", "amd64"} {
            if system == "windows" && arch != "amd64" { continue }
            asset := "ferri_" + version + "_" + system + "_" + arch
            if system == "windows" { asset += ".exe" }
            cmd := exec.Command("go", "build", "-trimpath", "-buildvcs=false", "-ldflags=-s -w", "-o", filepath.Join("dist", asset), ".")
            cmd.Env = append(os.Environ(), "GOOS=" + system, "GOARCH=" + arch, "CGO_ENABLED=0")
            cmd.Stdout, cmd.Stderr = os.Stdout, os.Stderr
            if err := cmd.Run(); err != nil { return err }
            binary, err := os.ReadFile(filepath.Join("dist", asset))
            if err != nil { return err }
            digest := fmt.Sprintf("%x", sha256.Sum256(binary))
            fmt.Fprintf(&checksums, "%s  %s\n", digest, asset)
            if system != "windows" {
                scope := "on_arm"
                if arch == "amd64" { scope = "on_intel" }
                fmt.Fprintf(&formula, `    %s do
      url "https://github.com/leo1394/homebrew-ferri/releases/download/v%s/%s", using: :nounzip
      sha256 "%s"
    end
`, scope, version, asset, digest)
            }
            fmt.Println("Built", asset)
        }
        if system != "windows" { fmt.Fprint(&formula, "  end\n\n") }
    }
    fmt.Fprint(&formula, `  def install
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
`)
    fmt.Fprintf(&formula, `    output = shell_output("#{bin}/ferri --version")
    assert_match "ferri version %s (", output
    assert_match(%%r{\(\d{4}-\d{2}-\d{2}\)\nhttps://github.com/leo1394/homebrew-ferri\n\z}, output)
`, version)
    fmt.Fprint(&formula, `    assert_match "--target", shell_output("#{bin}/ferri --help")
    assert_match "Did you mean '--target'", shell_output("#{bin}/ferri --targte app.apk 2>&1", 2)
    assert_path_exists bash_completion/"ferri"
    assert_path_exists zsh_completion/"_ferri"
    assert_path_exists fish_completion/"ferri.fish"
    assert_path_exists pwsh_completion/"ferri.ps1"
  end
end
`)
    if err := os.WriteFile("dist/SHA256SUMS", []byte(checksums.String()), 0o644); err != nil { return err }
    return os.WriteFile("Formula/ferri.rb", []byte(formula.String()), 0o644)
}

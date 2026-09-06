package main

import (
    "archive/zip"
    "bytes"
    "context"
    "errors"
    "os"
    "path/filepath"
    "strings"
    "testing"

    "howett.net/plist"
)

func identityArchive(t *testing.T, entries map[string][]byte) []byte {
    t.Helper()
    var buffer bytes.Buffer
    writer := zip.NewWriter(&buffer)
    for name, data := range entries {
        file, err := writer.Create(name)
        if err != nil { t.Fatal(err) }
        if _, err := file.Write(data); err != nil { t.Fatal(err) }
    }
    if err := writer.Close(); err != nil { t.Fatal(err) }
    return buffer.Bytes()
}

func identityFixture(t *testing.T, path string) {
    t.Helper()
    apk := identityArchive(t, map[string][]byte{"AndroidManifest.xml": []byte(`<manifest package="com.example.app"/>`)})
    data := apk
    if strings.EqualFold(filepath.Ext(path), ".ipa") {
        info, err := plist.Marshal(map[string]string{"CFBundleIdentifier":"com.example.app"}, plist.BinaryFormat)
        if err != nil { t.Fatal(err) }
        data = identityArchive(t, map[string][]byte{"Payload/App.app/Info.plist":info})
    }
    if strings.EqualFold(filepath.Ext(path), ".apks") { data = identityArchive(t, map[string][]byte{"splits/base-master.apk":apk}) }
    if err := os.WriteFile(path, data, 0o600); err != nil { t.Fatal(err) }
}

func TestInstallFallbackConsent(t *testing.T) {
    cases := []struct {
        name, answer string
        initialOK, absent, noninteractive, uninstallFails, retryFails bool
        installs, uninstalls int
    }{
        {name:"successful update preserves data", initialOK:true, installs:1},
        {name:"confirmed retry", answer:"yes\n", installs:2, uninstalls:1},
        {name:"default no", answer:"\n", installs:1},
        {name:"declined", answer:"n\n", installs:1},
        {name:"invalid response", answer:"maybe\n", installs:1},
        {name:"EOF", installs:1},
        {name:"noninteractive", answer:"yes\n", noninteractive:true, installs:1},
        {name:"different app only", absent:true, answer:"yes\n", installs:1},
        {name:"uninstall fails", answer:"y\n", uninstallFails:true, installs:1, uninstalls:1},
        {name:"retry fails once", answer:"y\n", retryFails:true, installs:2, uninstalls:1},
    }
    for _, ext := range []string{".apk", ".ipa", ".apks", ".aab"} {
        for _, item := range cases {
            t.Run(ext+"/"+item.name, func(t *testing.T) {
                platform, toolName := "android", "adb"
                if ext == ".ipa" { platform, toolName = "ios", "ios" }
                fakeTool(t, toolName)
                if ext == ".apks" || ext == ".aab" {
                    fakeTool(t, "bundletool")
                    self, _ := os.Executable()
                    t.Setenv("FERRI_JAVA", self)
                    t.Setenv("FERRI_TEST_JAVA", "1")
                }
                path := filepath.Join(t.TempDir(), "app"+ext)
                identityFixture(t, path)
                a := testApp(t)
                a.interactive, a.in = !item.noninteractive, strings.NewReader(item.answer)
                installs, uninstalls, queries := 0, 0, 0
                a.run = func(_ context.Context, _ bool, _ string, args ...string) (string, error) {
                    line := strings.Join(args, " ")
                    for _, arg := range args {
                        if strings.HasPrefix(arg, "--output=") { identityFixture(t, strings.TrimPrefix(arg, "--output=")); return "", nil }
                    }
                    if !strings.Contains(line, "chosen") { t.Fatal("Wrong device", line) }
                    if strings.Contains(line, "list") {
                        queries++
                        if installs != 1 { t.Fatal("Queried before failed installation") }
                        if item.absent {
                            if platform == "ios" { return "com.example.app.other Other 1.0", nil }
                            return "package:com.example.app.other", nil
                        }
                        if platform == "ios" { return "com.example.app Example 1.0", nil }
                        return "package:com.example.app", nil
                    }
                    if args[0] == "uninstall" || (len(args) > 2 && args[2] == "uninstall") {
                        uninstalls++
                        if installs != 1 || queries != 1 { t.Fatal("Wrong uninstall order") }
                        if !strings.Contains(a.out.(*bytes.Buffer).String(), "permanently deletes") { t.Fatal("Missing risk warning") }
                        if item.uninstallFails { return "", errors.New("uninstall failed") }
                        return "Success", nil
                    }
                    installs++
                    if installs == 1 && !item.initialOK { return "", errors.New("original install failure") }
                    if installs > 1 && (uninstalls != 1 || queries != 1) { t.Fatal("Retry without confirmed uninstall") }
                    if item.retryFails { return "", errors.New("retry failed") }
                    return "", nil
                }
                err := a.install(path, device{platform:platform,id:"chosen"})
                wantSuccess := item.initialOK || (item.installs == 2 && !item.retryFails)
                if (err == nil) != wantSuccess { t.Fatal(err) }
                if installs != item.installs || uninstalls != item.uninstalls { t.Fatal(installs, uninstalls) }
                if item.initialOK && queries != 0 { t.Fatal("Inspected app after successful update") }
                if item.uninstalls == 0 && !item.initialOK && !strings.Contains(err.Error(), "original install failure") { t.Fatal("Original failure lost", err) }
            })
        }
    }
}

func TestIdentityRejectsMixedAPKSAndInvalidPackage(t *testing.T) {
    a := identityArchive(t, map[string][]byte{"AndroidManifest.xml":[]byte(`<manifest package="com.example.a"/>`)})
    b := identityArchive(t, map[string][]byte{"AndroidManifest.xml":[]byte(`<manifest package="com.example.b"/>`)})
    path := filepath.Join(t.TempDir(), "mixed.apks")
    os.WriteFile(path, identityArchive(t, map[string][]byte{"a.apk":a,"b.apk":b}), 0o600)
    if _, err := packageID(path); err == nil { t.Fatal("Mixed identities accepted") }
    path = filepath.Join(t.TempDir(), "app.apk")
    os.WriteFile(path, identityArchive(t, map[string][]byte{"AndroidManifest.xml":[]byte(`<manifest package="x;bad"/>`)}), 0o600)
    if _, err := packageID(path); err == nil { t.Fatal("Invalid identity accepted") }
}

func TestBinaryAndroidManifest(t *testing.T) {
    data, err := os.ReadFile("tests/fixtures/AndroidManifest.axml")
    if err != nil { t.Fatal(err) }
    path := filepath.Join(t.TempDir(), "app.apk")
    if err := os.WriteFile(path, identityArchive(t, map[string][]byte{"AndroidManifest.xml":data}), 0o600); err != nil { t.Fatal(err) }
    id, err := packageID(path)
    if err != nil || id != "net.sorablue.shogo.FWMeasure" { t.Fatal(id, err) }
}

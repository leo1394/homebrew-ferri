package main

import (
    "archive/zip"
    "bytes"
    "encoding/xml"
    "errors"
    "fmt"
    "io"
    "os"
    "path/filepath"
    "regexp"
    "strings"

    "github.com/shogo82148/androidbinary"
    "howett.net/plist"
)

// Both parsers are compiled into Ferri; no extra device tools or runtimes are needed.
func packageID(target string) (string, error) {
    archive, err := zip.OpenReader(target)
    if err != nil { return "", fmt.Errorf("Read package identity: %w", err) }
    defer archive.Close()
    extension := strings.ToLower(filepath.Ext(target))
    if extension == ".apks" { return apksID(archive.File) }
    var entries []*zip.File
    for _, file := range archive.File {
        if extension == ".apk" && file.Name == "AndroidManifest.xml" { entries = append(entries, file) }
        parts := strings.Split(file.Name, "/")
        if extension == ".ipa" && len(parts) == 3 && parts[0] == "Payload" && strings.HasSuffix(parts[1], ".app") && parts[2] == "Info.plist" { entries = append(entries, file) }
    }
    if len(entries) != 1 { return "", errors.New("Package must contain exactly one main app manifest; refusing to uninstall anything") }
    data, err := readMetadata(entries[0])
    if err != nil { return "", err }
    id := ""
    if extension == ".ipa" {
        var info struct { ID string `plist:"CFBundleIdentifier"` }
        if _, err := plist.Unmarshal(data, &info); err != nil { return "", fmt.Errorf("Read IPA bundleId: %w", err) }
        id = info.ID
    } else {
        var manifest struct { Package string `xml:"package,attr"` }
        reader := io.Reader(bytes.NewReader(data))
        if !bytes.HasPrefix(bytes.TrimSpace(data), []byte("<")) {
            binary, err := androidbinary.NewXMLFile(bytes.NewReader(data))
            if err != nil { return "", fmt.Errorf("Read APK applicationId: %w", err) }
            reader = binary.Reader()
        }
        if err := xml.NewDecoder(reader).Decode(&manifest); err != nil { return "", fmt.Errorf("Read APK manifest: %w", err) }
        id = manifest.Package
    }
    if !regexp.MustCompile(`^[A-Za-z0-9_]+(?:[.-][A-Za-z0-9_]+)*$`).MatchString(id) {
        return "", errors.New("Missing or invalid applicationId/bundleId; refusing to uninstall anything")
    }
    return id, nil
}

func readMetadata(file *zip.File) ([]byte, error) {
    const limit = 16 << 20
    if file.UncompressedSize64 > limit { return nil, errors.New("App manifest exceeds 16 MiB") }
    reader, err := file.Open()
    if err != nil { return nil, err }
    defer reader.Close()
    data, err := io.ReadAll(io.LimitReader(reader, limit+1))
    if err != nil { return nil, err }
    if len(data) > limit { return nil, errors.New("App manifest exceeds 16 MiB") }
    return data, nil
}

func apksID(files []*zip.File) (string, error) {
    folder, err := os.MkdirTemp("", "ferri-identity-*")
    if err != nil { return "", err }
    defer os.RemoveAll(folder)
    id := ""
    for _, entry := range files {
        if !strings.HasSuffix(strings.ToLower(entry.Name), ".apk") { continue }
        reader, err := entry.Open()
        if err != nil { return "", err }
        path := filepath.Join(folder, "part.apk")
        file, err := os.Create(path)
        if err != nil { reader.Close(); return "", err }
        size, copyErr := io.Copy(file, io.LimitReader(reader, maxPackageBytes+1))
        closeErr := file.Close()
        reader.Close()
        if copyErr != nil { return "", copyErr }
        if closeErr != nil { return "", closeErr }
        if size > maxPackageBytes { return "", errors.New("APKS entry exceeds 8 GiB") }
        found, err := packageID(path)
        if err != nil { return "", err }
        if id != "" && id != found { return "", errors.New("APKS contains different application IDs; refusing to uninstall anything") }
        id = found
    }
    if id == "" { return "", errors.New("APKS contains no APK applicationId") }
    return id, nil
}

func (a *app) confirmRemoval(target string, selected device, tool string) error {
    id, err := packageID(target)
    if err != nil { return err }
    var output string
    if selected.platform == "android" {
        output, err = a.run(a.ctx, true, tool, "-s", selected.id, "shell", "pm", "list", "packages", id)
    } else {
        output, err = a.run(a.ctx, true, tool, "apps", "--list", "--udid="+selected.id)
    }
    if err != nil { return fmt.Errorf("Check existing app %s: %w", id, err) }
    installed := false
    for _, line := range strings.Split(output, "\n") {
        fields := strings.Fields(line)
        if len(fields) == 0 { continue }
        if selected.platform == "android" {
            if !strings.HasPrefix(fields[0], "package:") { return errors.New("Unexpected Android package list; refusing to continue") }
            installed = installed || fields[0] == "package:"+id
        } else { installed = installed || fields[0] == id }
    }
    if !installed { return errors.New("No installed app with the same ID; nothing was uninstalled") }
    if !a.interactive { return errors.New("Existing app found; refusing to uninstall in a non-interactive session. Retry in a terminal to review the data-loss warning") }
    fmt.Fprintf(a.out, "Installation failed, and %s is already installed on %s.\nWARNING: Uninstalling permanently deletes this app's local data. If reinstallation fails, Ferri cannot restore the old app or its data.\nUninstall this app and retry installation? [y/N]: ", id, selected.id)
    answer, err := a.readLine()
    if err != nil || (strings.ToLower(strings.TrimSpace(answer)) != "y" && strings.ToLower(strings.TrimSpace(answer)) != "yes") {
        return errors.New("Uninstall cancelled; existing app was not removed")
    }
    if a.ctx.Err() != nil { return a.ctx.Err() }
    fmt.Fprintf(a.out, "Uninstalling existing %s from %s; its local app data will be deleted.\n", id, selected.id)
    if selected.platform == "android" {
        output, err = a.run(a.ctx, true, tool, "-s", selected.id, "uninstall", id)
        if err == nil && strings.TrimSpace(output) != "Success" { err = fmt.Errorf("Uninstall did not succeed: %s", strings.TrimSpace(output)) }
    } else {
        _, err = a.run(a.ctx, false, tool, "uninstall", id, "--udid="+selected.id)
    }
    if err != nil { return fmt.Errorf("Uninstall %s failed; new package was not installed: %w", id, err) }
    return nil
}

// Attempt a normal update first. A destructive fallback requires explicit consent.
func (a *app) installWithFallback(target string, selected device, tool string, install func() error) error {
    initial := install()
    if initial == nil { return nil }
    if a.ctx.Err() != nil { return errors.Join(initial, a.ctx.Err()) }
    if err := a.confirmRemoval(target, selected, tool); err != nil { return errors.Join(initial, err) }
    fmt.Fprintln(a.out, "Retrying installation after confirmed uninstall...")
    if err := install(); err != nil { return fmt.Errorf("Reinstallation failed after uninstall; the previous app and its data cannot be restored: %w", err) }
    return nil
}

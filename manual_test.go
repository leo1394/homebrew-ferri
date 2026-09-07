package main

import (
    "bytes"
    "strings"
    "testing"
)

func TestManualOutput(t *testing.T) {
    a := testApp(t)
    if err := a.execute([]string{"__man"}); err != nil { t.Fatal(err) }
    output := a.out.(*bytes.Buffer).String()
    for _, expected := range []string{".TH FERRI 1", version, versionDate, ".SH OPTIONS", "Uninstalling deletes local app data"} {
        if !strings.Contains(output, expected) { t.Fatalf("Manual missing %q", expected) }
    }
    if strings.Contains(output, "@VERSION@") || strings.Contains(output, "@DATE@") { t.Fatal("Unexpanded manual metadata") }
}

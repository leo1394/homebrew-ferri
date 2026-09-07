package main

import (
    _ "embed"
    "strings"
)

//go:embed man/ferri.1
var manualTemplate string

func manual() string {
    return strings.NewReplacer("@VERSION@", version, "@DATE@", versionDate).Replace(manualTemplate)
}

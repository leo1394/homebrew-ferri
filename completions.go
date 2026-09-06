package main

import (
    "embed"
    "fmt"
)

//go:embed completions/*
var completionFiles embed.FS

func completion(shell string) (string, error) {
    switch shell {
    case "bash", "zsh", "fish", "powershell":
        data, err := completionFiles.ReadFile("completions/" + shell)
        return string(data), err
    }
    return "", fmt.Errorf("Expected __completion bash|zsh|fish|powershell")
}

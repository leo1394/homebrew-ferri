[CmdletBinding()]
param(
    [string]$Version = $env:FERRI_VERSION,
    [string]$InstallDir = "$env:LOCALAPPDATA\Ferri",
    [string]$Repository = 'leo1394/homebrew-ferri',
    [switch]$Local
)
$ErrorActionPreference = 'Stop'
if (-not [IO.Path]::IsPathRooted($InstallDir)) { throw 'InstallDir must be an absolute path.' }
$temp = Join-Path ([IO.Path]::GetTempPath()) ([guid]::NewGuid().ToString())
New-Item -ItemType Directory -Path $temp | Out-Null
try {
    $source = Join-Path $temp 'ferri.exe'
    if ($Local) {
        Copy-Item -LiteralPath (Join-Path $PSScriptRoot 'bin/ferri.exe') -Destination $source
    } else {
        if (-not [Environment]::Is64BitOperatingSystem) { throw 'Ferri requires 64-bit Windows.' }
        if (-not $Version) {
            $Version = (Invoke-RestMethod "https://raw.githubusercontent.com/$Repository/master/VERSION.txt").Trim()
        }
        $Version = $Version -replace '^v', ''
        if ($Version -notmatch '^\d+\.\d+\.\d+$') { throw 'Expected a version such as 0.1.0' }
        $asset = "ferri_${Version}_windows_amd64.exe"
        $base = "https://github.com/$Repository/releases/download/v$Version"
        Invoke-WebRequest "$base/$asset" -OutFile $source -UseBasicParsing
        $checksumFile = Join-Path $temp 'SHA256SUMS'
        Invoke-WebRequest "$base/SHA256SUMS" -OutFile $checksumFile -UseBasicParsing
        $checksums = Get-Content -LiteralPath $checksumFile -Raw
        $pattern = '(?m)^([0-9a-f]{64})\s+' + [regex]::Escape($asset) + '\s*$'
        if ($checksums -notmatch $pattern) { throw 'Missing release checksum' }
        if ((Get-FileHash $source -Algorithm SHA256).Hash.ToLowerInvariant() -ne $Matches[1]) { throw 'SHA256 verification failed' }
        $reported = @(& $source --version)
        if ($LASTEXITCODE -ne 0 -or $reported.Count -lt 1 -or $reported[0] -notmatch ('^ferri version ' + [regex]::Escape($Version) + ' \(\d{4}-\d{2}-\d{2}\)$')) { throw 'Version mismatch' }
    }
    $completion = & $source __completion powershell
    if ($LASTEXITCODE -ne 0) { throw 'Completion generation failed' }
    New-Item -ItemType Directory -Force -Path $InstallDir | Out-Null
    Copy-Item -LiteralPath $source -Destination (Join-Path $InstallDir 'ferri.exe') -Force
    Set-Content -LiteralPath (Join-Path $InstallDir 'ferri-completion.ps1') -Value $completion -Encoding UTF8
    $userPath = [string][Environment]::GetEnvironmentVariable('Path', 'User')
    if ($InstallDir -notin ($userPath -split ';')) {
        [Environment]::SetEnvironmentVariable('Path', (($userPath.TrimEnd(';') + ';' + $InstallDir).TrimStart(';')), 'User')
    }
    if ($InstallDir -notin ($env:Path -split ';')) { $env:Path += ";$InstallDir" }
    Write-Host "Installed Ferri to $InstallDir. Open a new terminal to use ferri."
    Write-Host "For PowerShell 7 completion, add this line to your `$PROFILE:"
    Write-Host (". '" + (Join-Path $InstallDir 'ferri-completion.ps1').Replace("'", "''") + "'")
} finally {
    Remove-Item -LiteralPath $temp -Recurse -Force
}

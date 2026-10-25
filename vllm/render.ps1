<#
.SYNOPSIS
    Render the vLLM launch config for DeepSeek-V4.1-Flash.

.EXAMPLE
    powershell -ExecutionPolicy Bypass -File vllm/render.ps1

.EXAMPLE
    powershell -ExecutionPolicy Bypass -File vllm/render.ps1 `
        -Config vllm/params/multi-h200-2x8-ray.json `
        -OutFile vllm/out/ray.json

.EXAMPLE
    powershell -ExecutionPolicy Bypass -File vllm/render.ps1 `
        -Config vllm/params/single-h200-8gpu.json -Yaml
#>
[CmdletBinding()]
param(
    [Parameter(Position = 0)]
    [string]$Config = "vllm/params/single-h200-8gpu.json",

    [string]$OutFile,

    [switch]$Yaml
)

$ErrorActionPreference = "Stop"
$repo = Split-Path -Parent $PSScriptRoot
Push-Location $repo

try {
    $jsonnetArgs = @("vllm/main.jsonnet", "--tla-code-file", "config=$Config")
    if ($Yaml) {
        $jsonnetArgs = @("-y") + $jsonnetArgs
    }

    if (-not $OutFile) {
        & jsonnet @jsonnetArgs
        if ($LASTEXITCODE -ne 0) {
            throw "jsonnet failed with exit code $LASTEXITCODE"
        }
        return
    }

    $output = & jsonnet @jsonnetArgs
    if ($LASTEXITCODE -ne 0) {
        throw "jsonnet failed with exit code $LASTEXITCODE"
    }

    $outPath = if ([System.IO.Path]::IsPathRooted($OutFile)) {
        $OutFile
    } else {
        Join-Path $repo $OutFile
    }

    $outDir = Split-Path -Parent $outPath
    if ($outDir -and -not (Test-Path $outDir)) {
        New-Item -ItemType Directory -Path $outDir -Force | Out-Null
    }

    # Write UTF-8 without BOM so other tools read Chinese text correctly.
    # Note: keep this script ASCII-only; Windows PowerShell 5.1 parses
    # BOM-less UTF-8 scripts as ANSI and would break non-ASCII literals.
    $encoding = New-Object -TypeName System.Text.UTF8Encoding -ArgumentList $false
    [System.IO.File]::WriteAllText($outPath, (($output -join "`n") + "`n"), $encoding)
    Write-Host "Wrote $outPath"
}
finally {
    Pop-Location
}

# Run Jsonnet assertions and render every params file.
# Usage: powershell -ExecutionPolicy Bypass -File vllm/run-tests.ps1
# Keep this script ASCII-only for Windows PowerShell 5.1 compatibility.

$ErrorActionPreference = "Stop"
$repo = Split-Path -Parent $PSScriptRoot
Push-Location $repo

try {
    & jsonnet vllm/tests.jsonnet | Out-Null
    if ($LASTEXITCODE -ne 0) {
        throw "vllm/tests.jsonnet failed"
    }

    $params = Get-ChildItem -Path (Join-Path $repo "vllm/params") -Filter "*.json" |
        Sort-Object Name

    foreach ($p in $params) {
        & jsonnet vllm/main.jsonnet --tla-code-file "config=$($p.FullName)" | Out-Null
        if ($LASTEXITCODE -ne 0) {
            throw "render failed: $($p.Name)"
        }
    }

    Write-Host "OK: assertions passed; rendered $($params.Count) params files."
}
finally {
    Pop-Location
}

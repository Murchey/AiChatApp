param(
    [int]$Port = 8080,
    [string]$DataDir = (Join-Path $PSScriptRoot '..\data')
)

$ErrorActionPreference = 'Stop'
$projectRoot = Resolve-Path (Join-Path $PSScriptRoot '..')
$dataPath = [System.IO.Path]::GetFullPath($DataDir)
New-Item -ItemType Directory -Force -Path $dataPath | Out-Null
$env:AICHAT_PORT = [string]$Port
$env:AICHAT_DATA_DIR = $dataPath
if ([string]::IsNullOrWhiteSpace($env:AICHAT_TOKEN_PEPPER)) {
    Write-Warning 'AICHAT_TOKEN_PEPPER is empty; this is acceptable only for M0 local health checks.'
}

Push-Location $projectRoot
try {
    & .\gradlew.bat bootRun
    if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }
}
finally {
    Pop-Location
}

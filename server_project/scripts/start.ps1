param(
    [int]$Port = 8080,
    [string]$DataDir = (Join-Path $PSScriptRoot '..\data'),
    [switch]$Build
)

$ErrorActionPreference = 'Stop'
$root = [System.IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
$data = [System.IO.Path]::GetFullPath($DataDir)
New-Item -ItemType Directory -Force -Path $data | Out-Null
$env:AICHAT_PORT = "$Port"
$env:AICHAT_DATA_DIR = $data

Push-Location $root
try {
    if ($Build) { & .\gradlew.bat bootJar }
    $jar = Join-Path $root 'build\libs\aichat-backend.jar'
    if (Test-Path $jar) {
        & java -jar $jar
    } else {
        & .\gradlew.bat bootRun
    }
    exit $LASTEXITCODE
} finally { Pop-Location }


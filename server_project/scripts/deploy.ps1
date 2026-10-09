param(
    [string]$InstallDir = (Join-Path $env:LOCALAPPDATA 'AiChat\server'),
    [int]$Port = 8080,
    [switch]$SkipTests
)

$ErrorActionPreference = 'Stop'
$root = [System.IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
New-Item -ItemType Directory -Force -Path $InstallDir, (Join-Path $InstallDir 'data') | Out-Null
Push-Location $root
try {
    if (-not $SkipTests) { & .\gradlew.bat test }
    & .\gradlew.bat bootJar
    Copy-Item .\build\libs\aichat-backend.jar (Join-Path $InstallDir 'aichat-backend.jar') -Force
    @"
AICHAT_PORT=$Port
AICHAT_DATA_DIR=$(Join-Path $InstallDir 'data')
"@ | Set-Content (Join-Path $InstallDir 'aichat.env') -Encoding utf8
    Write-Host "部署完成：$InstallDir"
    Write-Host "启动命令：java -jar `"$(Join-Path $InstallDir 'aichat-backend.jar')`""
} finally { Pop-Location }


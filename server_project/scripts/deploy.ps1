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
    & "$PSScriptRoot\build.ps1" -SkipTests:$SkipTests
    Copy-Item .\build\libs\aichat-backend.jar (Join-Path $InstallDir 'aichat-backend.jar') -Force
    if (-not (Test-Path (Join-Path $InstallDir 'aichat.env'))) { @"
AICHAT_PORT=$Port
AICHAT_DATA_DIR=$(Join-Path $InstallDir 'data')
"@ | Set-Content (Join-Path $InstallDir 'aichat.env') -Encoding utf8 }
    Copy-Item (Join-Path $PSScriptRoot 'launch.ps1') (Join-Path $InstallDir 'launch.ps1') -Force
    Write-Host "部署完成：$InstallDir"
    Write-Host "启动命令：& `"$(Join-Path $InstallDir 'launch.ps1')`""
} finally { Pop-Location }


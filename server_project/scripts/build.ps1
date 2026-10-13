param([switch]$SkipTests)
$ErrorActionPreference = 'Stop'
$root = [System.IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
Push-Location (Join-Path $root 'admin-panel')
try {
    if (-not (Test-Path 'node_modules')) {
        & npm.cmd ci
        if ($LASTEXITCODE -ne 0) { throw '管理面板依赖安装失败' }
    }
    & npm.cmd run build
    if ($LASTEXITCODE -ne 0) { throw '管理面板构建失败' }
} finally { Pop-Location }
Push-Location $root
try {
    if (-not $SkipTests) {
        & .\gradlew.bat test
        if ($LASTEXITCODE -ne 0) { throw '后端测试失败，未生成部署包' }
    }
    & .\gradlew.bat bootJar
    if ($LASTEXITCODE -ne 0) { throw '后端打包失败' }
} finally { Pop-Location }

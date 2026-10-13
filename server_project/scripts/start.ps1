param(
    [int]$Port = 8080,
    [string]$DataDir = (Join-Path $PSScriptRoot '..\data'),
    [switch]$Build,
    [switch]$SkipBuild,
    [string]$EnvFile = (Join-Path $PSScriptRoot '..\config\local.env')
)

$ErrorActionPreference = 'Stop'
$root = [System.IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
$data = [System.IO.Path]::GetFullPath($DataDir)
New-Item -ItemType Directory -Force -Path $data | Out-Null
if (Test-Path -LiteralPath $EnvFile) {
    foreach ($line in Get-Content -LiteralPath $EnvFile) {
        if ($line -match '^\s*(AICHAT_[A-Z0-9_]+)=(.*)$') {
            [Environment]::SetEnvironmentVariable($Matches[1], $Matches[2].Trim(), 'Process')
        }
    }
}
if ($PSBoundParameters.ContainsKey('Port') -or -not $env:AICHAT_PORT) { $env:AICHAT_PORT = "$Port" }
$env:AICHAT_DATA_DIR = $data

Push-Location $root
try {
    if ($Build -or -not $SkipBuild) { & "$PSScriptRoot\build.ps1" -SkipTests }
    $jar = Join-Path $root 'build\libs\aichat-backend.jar'
    if (Test-Path $jar) {
        & java -jar $jar
    } else {
        throw 'JAR 不存在，请先运行 scripts\build.ps1'
    }
    exit $LASTEXITCODE
} finally { Pop-Location }


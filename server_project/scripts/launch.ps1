$ErrorActionPreference = 'Stop'
# Copied beside the installed JAR and aichat.env by deploy.ps1.
foreach ($line in Get-Content -LiteralPath (Join-Path $PSScriptRoot 'aichat.env')) {
    if ($line -match '^\s*(AICHAT_[A-Z0-9_]+)=(.*)$') {
        [Environment]::SetEnvironmentVariable($Matches[1], $Matches[2].Trim(), 'Process')
    }
}
Push-Location $PSScriptRoot
try { & java -jar (Join-Path $PSScriptRoot 'aichat-backend.jar'); exit $LASTEXITCODE }
finally { Pop-Location }

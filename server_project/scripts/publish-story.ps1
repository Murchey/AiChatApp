param(
    [Parameter(Mandatory = $true)][string]$Path,
    [string]$BaseUrl = 'http://127.0.0.1:8080',
    [Parameter(Mandatory = $true)][string]$AdminToken
)

$ErrorActionPreference = 'Stop'
& (Join-Path $PSScriptRoot 'validate-story.ps1') -Path $Path
$body = Get-Content -LiteralPath (Resolve-Path -LiteralPath $Path) -Raw
Invoke-RestMethod -Method Post -Uri ($BaseUrl.TrimEnd('/') + '/api/admin/stories/publish') `
    -Headers @{ 'X-Admin-Token' = $AdminToken } -ContentType 'application/json' -Body $body

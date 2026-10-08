param(
    [string]$BaseUrl = 'http://127.0.0.1:8080',
    [Parameter(Mandatory = $true)][string]$AdminToken,
    [int]$MaxUses = 1,
    [int]$ExpiresInHours = 0
)

$ErrorActionPreference = 'Stop'
$body = @{ maxUses = $MaxUses; expiresInHours = $ExpiresInHours } | ConvertTo-Json
Invoke-RestMethod -Method Post -Uri ($BaseUrl.TrimEnd('/') + '/api/admin/invites') `
    -Headers @{ 'X-Admin-Token' = $AdminToken } -ContentType 'application/json' -Body $body

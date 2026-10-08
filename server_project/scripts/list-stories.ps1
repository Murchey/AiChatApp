param(
    [string]$BaseUrl = 'http://127.0.0.1:8080',
    [string]$Query,
    [string]$Tag,
    [int]$Limit = 20,
    [string]$Token
)

$ErrorActionPreference = 'Stop'
$query = @("limit=$Limit")
if ($Query) { $query += 'q=' + [Uri]::EscapeDataString($Query) }
if ($Tag) { $query += 'tag=' + [Uri]::EscapeDataString($Tag) }
$headers = @{}
if ($Token) { $headers.Authorization = "Bearer $Token" }
Invoke-RestMethod -Method Get -Uri (($BaseUrl.TrimEnd('/') + '/api/stories?' + ($query -join '&'))) -Headers $headers

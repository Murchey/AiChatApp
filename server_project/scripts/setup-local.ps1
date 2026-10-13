param([int]$Port = 8080)
$ErrorActionPreference = 'Stop'
$config = Join-Path $PSScriptRoot '..\config\local.env'
if (Test-Path -LiteralPath $config) {
    Write-Host '本地配置已存在，保留原有密钥和配置。'
    return
}
function New-LocalSecret {
    $bytes = New-Object byte[] 32
    $rng = [System.Security.Cryptography.RandomNumberGenerator]::Create()
    try { $rng.GetBytes($bytes) } finally { $rng.Dispose() }
    return ([System.BitConverter]::ToString($bytes)).Replace('-', '').ToLowerInvariant()
}
$pepper = New-LocalSecret
$admin = New-LocalSecret
$configuration = @"
AICHAT_PORT=$Port
AICHAT_BIND_ADDRESS=0.0.0.0
AICHAT_TOKEN_PEPPER=$pepper
AICHAT_REQUIRE_TOKEN_PEPPER=true
AICHAT_BOOTSTRAP_ADMIN_TOKEN=$admin
AICHAT_FEATURE_STORIES=true
AICHAT_FEATURE_CHARACTERS=true
AICHAT_FEATURE_COMMENTS=true
AICHAT_FEATURE_ADMIN_PUBLISH=true
AICHAT_INVITE_REQUIRED=true
"@
[System.IO.File]::WriteAllText([System.IO.Path]::GetFullPath($config), $configuration.Replace("`r`n", "`n") + "`n", (New-Object System.Text.UTF8Encoding($false)))
Write-Host "本地配置已创建：$([System.IO.Path]::GetFullPath($config))"
Write-Host '管理员令牌位于该文件的 AICHAT_BOOTSTRAP_ADMIN_TOKEN。执行 scripts\start.ps1 启动。'

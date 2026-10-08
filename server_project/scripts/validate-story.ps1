param(
    [Parameter(Mandatory = $true)][string]$Path
)

$ErrorActionPreference = 'Stop'
$resolved = (Resolve-Path -LiteralPath $Path).Path
$json = Get-Content -LiteralPath $resolved -Raw | ConvertFrom-Json
$errors = [System.Collections.Generic.List[string]]::new()
if ($json.schemaVersion -ne 1) { $errors.Add('schemaVersion 必须为 1') }
if ([string]::IsNullOrWhiteSpace($json.storyId) -or $json.storyId -notmatch '^[A-Za-z0-9][A-Za-z0-9._-]{1,127}$') { $errors.Add('storyId 格式无效') }
if ([string]::IsNullOrWhiteSpace($json.title) -or $json.title.Length -gt 200) { $errors.Add('title 必须为 1-200 字符') }
if ($null -eq $json.chapters -or $json.chapters.Count -lt 1) { $errors.Add('chapters 至少需要一个章节') }
$ids = @{}
if ($null -ne $json.chapters) {
    foreach ($chapter in $json.chapters) {
        if ($null -eq $chapter.memories -or $chapter.memories.Count -lt 1) { $errors.Add("章节 $($chapter.id) 没有记忆点"); continue }
        foreach ($memory in $chapter.memories) {
            if ([string]::IsNullOrWhiteSpace($memory.id) -or $ids.ContainsKey($memory.id)) { $errors.Add("记忆点 ID 重复或为空: $($memory.id)") }
            else { $ids[$memory.id] = $true }
            if ([string]::IsNullOrWhiteSpace($memory.content) -or $memory.content.Length -gt 20000) { $errors.Add("记忆点正文无效: $($memory.id)") }
        }
    }
}
if ($errors.Count -gt 0) { $errors | ForEach-Object { Write-Error $_ }; exit 1 }
Write-Output "OK: $resolved ($($ids.Count) memories)"

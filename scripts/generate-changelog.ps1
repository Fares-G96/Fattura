<#
.SYNOPSIS
    يولّد نص Changelog من رسائل commits في Git بين آخر إصدار سابق (tag) والإصدار الحالي.
    الناتج نص Markdown بسيط يُستخدم كملاحظات الإصدار (Release Notes) المعروضة داخل نافذة التحديث.

.PARAMETER PreviousTag
    اسم التاج السابق (مثال: v1.1.0). اتركه فارغًا لو كان هذا أول إصدار على الإطلاق.

.PARAMETER CurrentTag
    اسم التاج الحالي الذي يجري إصداره الآن (مثال: v1.2.0).

.PARAMETER OutputPath
    أين يُكتب ملف CHANGELOG المولَّد (نص عادي/Markdown).

.EXAMPLE
    ./generate-changelog.ps1 -PreviousTag "v1.1.0" -CurrentTag "v1.2.0" -OutputPath "CHANGELOG.md"
#>
param(
    [Parameter(Mandatory = $false)] [string] $PreviousTag = "",
    [Parameter(Mandatory = $true)]  [string] $CurrentTag,
    [Parameter(Mandatory = $true)]  [string] $OutputPath
)

$ErrorActionPreference = "Stop"

Write-Host "Generating changelog for $CurrentTag (since: $(if ($PreviousTag) { $PreviousTag } else { 'repository start' }))"

if ($PreviousTag) {
    $range = "$PreviousTag..HEAD"
} else {
    $range = "HEAD"
}

# %s = عنوان الـ commit فقط (سطر واحد لكل commit)، --no-merges يستبعد commits الدمج التلقائية
$rawLog = git log $range --no-merges --pretty=format:"%s" 2>$null

if (-not $rawLog) {
    $rawLog = @("No changes recorded since the previous release.")
} else {
    $rawLog = $rawLog -split "`n"
}

# تصنيف بسيط حسب بادئات شائعة (Conventional Commits) إن وُجدت، وإلا قسم عام "Changes"
$categories = [ordered]@{
    "feat"     = "### ✨ Features"
    "fix"      = "### 🐛 Fixes"
    "perf"     = "### ⚡ Performance"
    "refactor" = "### 🔧 Refactoring"
    "docs"     = "### 📝 Documentation"
    "other"    = "### 📦 Other Changes"
}
$buckets = @{}
foreach ($key in $categories.Keys) { $buckets[$key] = @() }

foreach ($line in $rawLog) {
    $matched = $false
    foreach ($prefix in @("feat", "fix", "perf", "refactor", "docs")) {
        if ($line -match "^${prefix}(\(.+\))?:\s*(.+)") {
            $buckets[$prefix] += $Matches[2]
            $matched = $true
            break
        }
    }
    if (-not $matched) { $buckets["other"] += $line }
}

$sb = New-Object System.Text.StringBuilder
[void]$sb.AppendLine("## $CurrentTag")
[void]$sb.AppendLine("")

foreach ($key in $categories.Keys) {
    if ($buckets[$key].Count -eq 0) { continue }
    [void]$sb.AppendLine($categories[$key])
    foreach ($item in $buckets[$key]) {
        [void]$sb.AppendLine("- $item")
    }
    [void]$sb.AppendLine("")
}

$content = $sb.ToString()
Set-Content -Path $OutputPath -Value $content -Encoding UTF8

Write-Host "Changelog written to '$OutputPath'"
Write-Host $content

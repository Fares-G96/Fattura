<#
.SYNOPSIS
    يبني حزمتَي التحديث لإصدار جديد: full.zip (التطبيق كاملًا) وpatch.zip (الملفات المتغيّرة فقط
    مقارنة بالمانيفست السابق، إن وُجد). هذا ما يفعّل "التحديث الجزئي" الفعلي من جهة الخادم.

.PARAMETER PublishFolder
    مجلد النشر (نفس المجلد الذي وُلِّد منه manifest.json الحالي).

.PARAMETER CurrentManifestPath
    مسار manifest.json للإصدار الحالي (الناتج من generate-manifest.ps1).

.PARAMETER PreviousManifestPath
    مسار manifest.json للإصدار السابق إن كان متاحًا (يُنزَّل من الإصدار السابق على GitHub قبل
    استدعاء هذا السكربت). اتركه فارغًا لو لم يوجد إصدار سابق (أول إصدار على الإطلاق) — في هذه
    الحالة سيكون patch.zip مطابقًا لـ full.zip (كل الملفات "جديدة").

.PARAMETER OutputFolder
    أين تُكتب full.zip وpatch.zip الناتجتان.

.EXAMPLE
    ./build-packages.ps1 -PublishFolder "publish/InvoiceApp/Runtime" -CurrentManifestPath "publish/InvoiceApp/manifest.json" -PreviousManifestPath "previous-manifest.json" -OutputFolder "release-assets"
#>
param(
    [Parameter(Mandatory = $true)] [string] $PublishFolder,
    [Parameter(Mandatory = $true)] [string] $CurrentManifestPath,
    [Parameter(Mandatory = $false)] [string] $PreviousManifestPath = "",
    [Parameter(Mandatory = $true)] [string] $OutputFolder
)

$ErrorActionPreference = "Stop"

New-Item -ItemType Directory -Force -Path $OutputFolder | Out-Null

$currentManifest = Get-Content $CurrentManifestPath -Raw | ConvertFrom-Json

# ===== full.zip: التطبيق كاملًا (يُستخدم أيضًا كخطة بديلة تلقائية لو فشل التحديث الجزئي) =====
$fullZipPath = Join-Path $OutputFolder "full.zip"
if (Test-Path $fullZipPath) { Remove-Item $fullZipPath -Force }
Write-Host "Building full.zip from '$PublishFolder'..."
Compress-Archive -Path (Join-Path $PublishFolder '*') -DestinationPath $fullZipPath -CompressionLevel Optimal
Write-Host "  -> $fullZipPath ($((Get-Item $fullZipPath).Length) bytes)"

# ===== patch.zip: الملفات المتغيّرة فقط مقارنة بالإصدار السابق =====
$patchZipPath = Join-Path $OutputFolder "patch.zip"
if (Test-Path $patchZipPath) { Remove-Item $patchZipPath -Force }

$changedPaths = @()

if ($PreviousManifestPath -and (Test-Path $PreviousManifestPath)) {
    $previousManifest = Get-Content $PreviousManifestPath -Raw | ConvertFrom-Json
    $previousByPath = @{}
    foreach ($f in $previousManifest.Files) { $previousByPath[$f.RelativePath] = $f.Sha256 }

    foreach ($f in $currentManifest.Files) {
        $prevHash = $previousByPath[$f.RelativePath]
        if (-not $prevHash -or $prevHash -ne $f.Sha256) {
            $changedPaths += $f.RelativePath
        }
    }
    Write-Host "Previous manifest found: $($changedPaths.Count) of $($currentManifest.Files.Count) file(s) changed."
} else {
    Write-Host "No previous manifest available (first release) - patch.zip will include all files."
    $changedPaths = $currentManifest.Files | ForEach-Object { $_.RelativePath }
}

if ($changedPaths.Count -eq 0) {
    Write-Host "No files changed; patch.zip will just contain the manifest-listed files as a safety net."
    $changedPaths = $currentManifest.Files | ForEach-Object { $_.RelativePath }
}

# نبني مجلدًا مؤقتًا يحتوي فقط الملفات المتغيّرة، بنفس البنية النسبية، ثم نضغطه
$stagingDir = Join-Path $OutputFolder "_patch_staging"
if (Test-Path $stagingDir) { Remove-Item $stagingDir -Recurse -Force }
New-Item -ItemType Directory -Force -Path $stagingDir | Out-Null

foreach ($rel in $changedPaths) {
    $src = Join-Path $PublishFolder $rel
    $dest = Join-Path $stagingDir $rel
    New-Item -ItemType Directory -Force -Path (Split-Path $dest) | Out-Null
    Copy-Item $src $dest -Force
}

Compress-Archive -Path (Join-Path $stagingDir '*') -DestinationPath $patchZipPath -CompressionLevel Optimal
Remove-Item $stagingDir -Recurse -Force

Write-Host "  -> $patchZipPath ($((Get-Item $patchZipPath).Length) bytes, $($changedPaths.Count) file(s))"

Copy-Item $CurrentManifestPath (Join-Path $OutputFolder "manifest.json") -Force
Write-Host "Done. Assets ready in '$OutputFolder': full.zip, patch.zip, manifest.json"

<#
.SYNOPSIS
    يولّد manifest.json لمجلد نشر InvoiceApp: يسرد كل ملف بمساره النسبي، بصمة SHA256، والحجم.
    يُستخدم هذا الملف على جهاز المستخدم لتحديد أي الملفات تغيّرت فعليًا بين إصدارين (تحديث جزئي).

.PARAMETER PublishFolder
    مسار مجلد النشر (عادة publish\InvoiceApp\Runtime بعد dotnet publish).

.PARAMETER OutputPath
    أين يُكتب ملف manifest.json الناتج.

.PARAMETER Version
    رقم الإصدار الذي يُكتب داخل المانيفست نفسه (لأغراض تتبّع/تشخيص فقط).

.EXAMPLE
    ./generate-manifest.ps1 -PublishFolder "publish/InvoiceApp/Runtime" -OutputPath "publish/InvoiceApp/manifest.json" -Version "1.2.0"
#>
param(
    [Parameter(Mandatory = $true)] [string] $PublishFolder,
    [Parameter(Mandatory = $true)] [string] $OutputPath,
    [Parameter(Mandatory = $true)] [string] $Version
)

$ErrorActionPreference = "Stop"

if (-not (Test-Path $PublishFolder)) {
    throw "Publish folder not found: $PublishFolder"
}

# مهم: FullName من Get-ChildItem دومًا مسار مطلق، بينما $PublishFolder قد يُمرَّر نسبيًا (كما في
# سير عمل GitHub Actions). لو استخدمنا طول $PublishFolder النسبي مباشرة كنقطة قطع في FullName
# المطلق، سنقطع من مكان خاطئ تمامًا (تلف المسار النسبي لكل ملف). لذا نحوّله لمسار مطلق أولًا.
$PublishFolder = (Resolve-Path $PublishFolder).Path

Write-Host "Scanning '$PublishFolder' for files..."

$files = Get-ChildItem -Path $PublishFolder -Recurse -File

$entries = @()
foreach ($file in $files) {
    $relativePath = $file.FullName.Substring($PublishFolder.Length).TrimStart('\', '/').Replace('\', '/')

    # نتجاهل بيانات المستخدم ومجلد التحديث الداخلي، هذه ليست جزءًا من "التطبيق" القابل للاستبدال
    if ($relativePath -like "AppData/*" -or $relativePath -like "Updater/*") {
        continue
    }

    $hash = (Get-FileHash -Path $file.FullName -Algorithm SHA256).Hash.ToLower()

    $entries += [PSCustomObject]@{
        RelativePath = $relativePath
        Sha256       = $hash
        Size         = $file.Length
    }

    Write-Host "  $relativePath -> $hash"
}

$manifest = [PSCustomObject]@{
    Version        = $Version
    GeneratedAtUtc = (Get-Date).ToUniversalTime().ToString("o")
    Files          = $entries
}

$json = $manifest | ConvertTo-Json -Depth 5
Set-Content -Path $OutputPath -Value $json -Encoding UTF8

Write-Host ""
Write-Host "Manifest written to '$OutputPath' with $($entries.Count) file(s)."

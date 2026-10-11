param(
    [string]$Configuration = "Release",
    [string[]]$Rids = @("win-x64", "win-arm64", "linux-x64", "linux-arm64", "osx-x64", "osx-arm64"),
    [switch]$SelfContained,
    [string]$OutputPath = "RVZStudio\bin\Release",
    [switch]$NoZip
)

$ErrorActionPreference = "Stop"
$project = Join-Path $PSScriptRoot "RVZStudio\RVZStudio.csproj"

[xml]$projectXml = Get-Content $project
$version = @($projectXml.Project.PropertyGroup.FileVersion) |
    Where-Object { -not [string]::IsNullOrWhiteSpace($_) } |
    Select-Object -First 1
if ([string]::IsNullOrWhiteSpace($version)) { $version = "0.0.0" }

# The release path keeps every historical bundle next to the application build output, so it is
# never cleaned: only the ZIP for the version being published is refreshed.
$releasePath = if ([System.IO.Path]::IsPathRooted($OutputPath)) {
    $OutputPath
} else {
    Join-Path $PSScriptRoot $OutputPath
}
New-Item -ItemType Directory -Force -Path $releasePath | Out-Null

foreach ($rid in $Rids) {
    # Scratch directory for the publish output; removed before every run so old files cannot leak
    # into the bundle. This is the only folder the script clears.
    $out = Join-Path $PSScriptRoot "publish\$rid"
    if (Test-Path $out) { Remove-Item $out -Recurse -Force }

    $publishArgs = @(
        "publish", $project, "-c", $Configuration, "-r", $rid, "-o", $out,
        "-p:PublishSingleFile=true",
        "-p:IncludeNativeLibrariesForSelfExtract=true"
    )

    if ($SelfContained) {
        $publishArgs += @("--self-contained", "true")
    }
    else {
        # Default: framework-dependent single-file bundles (smaller; requires the .NET runtime).
        $publishArgs += @("--self-contained", "false")
    }

    Write-Host "Publishing $rid..." -ForegroundColor Cyan
    & dotnet @publishArgs
    if ($LASTEXITCODE -ne 0) {
        throw "Publish failed for $rid"
    }

    # Ship the license, readme and release notes with every bundle. The helper executables
    # (DolphinTool on Windows, 7za everywhere) are copied by the project itself and are kept
    # outside the single-file bundle so they can be launched as child processes.
    foreach ($file in @("LICENSE.txt", "ReadMe.md")) {
        $source = Join-Path $PSScriptRoot $file
        if (Test-Path $source) { Copy-Item $source $out -Force }
    }
    $whatsNew = Join-Path $PSScriptRoot "docs\WhatsNew.md"
    if (Test-Path $whatsNew) { Copy-Item $whatsNew (Join-Path $out "WhatsNew.md") -Force }

    if (-not $NoZip) {
        # The bundle name matches the documented release convention and the downloads the update
        # check points users to: release_<version>_<rid>.zip.
        $zipPath = Join-Path $releasePath "release_${version}_${rid}.zip"
        if (Test-Path $zipPath) { Remove-Item $zipPath -Force }
        Write-Host "Creating $([System.IO.Path]::GetFileName($zipPath))..." -ForegroundColor Cyan
        Compress-Archive -Path (Join-Path $out "*") -DestinationPath $zipPath
    }
}

Write-Host "All publish targets completed." -ForegroundColor Green

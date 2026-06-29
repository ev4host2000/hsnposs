#Requires -Version 5.1
# Build Flutter Windows release + compile Inno Setup -> dist\MizaPos-Setup.exe
# If Inno Setup is missing, downloads official innosetup-6.7.1.exe and installs silently to your user profile (no winget).
# Run from repo root:
#   powershell -ExecutionPolicy Bypass -File scripts\build_windows_installer.ps1

$ErrorActionPreference = "Stop"
$root = Resolve-Path (Join-Path $PSScriptRoot "..")
$appDir = Join-Path $root.Path "apps\mizapos_desktop"
Set-Location $appDir

function Find-SignTool {
    $candidates = @(
        (Join-Path ${env:ProgramFiles(x86)} "Windows Kits\10\bin\x64\signtool.exe"),
        (Join-Path ${env:ProgramFiles(x86)} "Windows Kits\10\bin\x86\signtool.exe"),
        (Join-Path $env:ProgramFiles "Windows Kits\10\bin\x64\signtool.exe"),
        (Join-Path $env:ProgramFiles "Windows Kits\10\bin\x86\signtool.exe")
    )
    foreach ($p in $candidates) {
        if ($p -and (Test-Path -LiteralPath $p)) { return $p }
    }
    $cmd = Get-Command "signtool.exe" -ErrorAction SilentlyContinue
    if ($cmd) { return $cmd.Source }
    return $null
}

function Try-CodeSignFile([string] $path, [string] $signTool) {
    if (-not $signTool) { return $false }
    if (-not (Test-Path -LiteralPath $path)) { return $false }

    Write-Host ">> Signing: $path" -ForegroundColor Cyan
    & $signTool sign /fd SHA256 /td SHA256 /tr "http://timestamp.digicert.com" /a $path
    if ($LASTEXITCODE -ne 0) {
        Write-Host "!! Signing failed (exit $LASTEXITCODE): $path" -ForegroundColor Yellow
        return $false
    }
    return $true
}

function Find-Iscc {
    $candidates = @(
        (Join-Path ${env:ProgramFiles(x86)} "Inno Setup 6\ISCC.exe"),
        (Join-Path $env:ProgramFiles "Inno Setup 6\ISCC.exe"),
        (Join-Path $env:LOCALAPPDATA "Programs\Inno Setup 6\ISCC.exe")
    )
    foreach ($p in $candidates) {
        if ($p -and (Test-Path -LiteralPath $p)) { return $p }
    }
    $cmd = Get-Command "ISCC.exe" -ErrorAction SilentlyContinue
    if ($cmd) { return $cmd.Source }
    return $null
}

function Ensure-InnoCompiler {
    $existing = Find-Iscc
    if ($existing) { return $existing }

    Write-Host ""
    Write-Host ">> Inno Setup 6 not found. Downloading official installer (silent, per-user)..." -ForegroundColor Yellow

    $innoRoot = Join-Path $env:LOCALAPPDATA "Programs\Inno Setup 6"
    $isccPath = Join-Path $innoRoot "ISCC.exe"
    if (Test-Path -LiteralPath $isccPath) { return $isccPath }

    $url = "https://github.com/jrsoftware/issrc/releases/download/is-6_7_1/innosetup-6.7.1.exe"
    $tmp = Join-Path $env:TEMP "innosetup-6.7.1-mizapos-build.exe"

    [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
    Invoke-WebRequest -Uri $url -OutFile $tmp -UseBasicParsing

    $dirArg = '/DIR="' + $innoRoot + '"'
    $proc = Start-Process -FilePath $tmp `
        -ArgumentList @("/VERYSILENT", "/SUPPRESSMSGBOXES", "/NORESTART", $dirArg) `
        -Wait -PassThru -NoNewWindow

    if ($proc.ExitCode -ne 0) {
        throw "Inno Setup silent install failed (exit $($proc.ExitCode)). Install manually from https://jrsoftware.org/isdl.php"
    }

    Start-Sleep -Seconds 3

    $again = Find-Iscc
    if ($again) { return $again }
    if (Test-Path -LiteralPath $isccPath) { return $isccPath }

    throw "ISCC.exe still not found after install. Tried: $isccPath and Program Files paths."
}

function Get-FullAppVersionFromPubspec([string] $pubspecPath) {
    if (-not (Test-Path -LiteralPath $pubspecPath)) {
        throw "pubspec.yaml not found: $pubspecPath"
    }

    $versionLine = Select-String -Path $pubspecPath -Pattern '^\s*version\s*:\s*([0-9A-Za-z\.\+\-]+)\s*$' | Select-Object -First 1
    if (-not $versionLine) {
        throw "Could not read version from pubspec.yaml"
    }

    $rawVersion = $versionLine.Matches[0].Groups[1].Value.Trim()
    if (-not $rawVersion) {
        throw "pubspec.yaml version is empty"
    }
    return $rawVersion
}

function Get-AppVersionFromPubspec([string] $pubspecPath) {
    $rawVersion = Get-FullAppVersionFromPubspec -pubspecPath $pubspecPath

    # Inno AppVersion expects semantic core version; drop Flutter build suffix after '+'.
    $innoVersion = ($rawVersion -split '\+')[0]
    if (-not $innoVersion) {
        throw "Invalid pubspec version format: $rawVersion"
    }

    return $innoVersion
}

function Read-Utf8Text([string] $path) {
    if (-not (Test-Path -LiteralPath $path)) {
        throw "UTF-8 text file not found: $path"
    }
    return [System.IO.File]::ReadAllText($path, [System.Text.UTF8Encoding]::new($true))
}

function Write-Utf8Json([string] $path, [string] $json) {
    $utf8NoBom = [System.Text.UTF8Encoding]::new($false)
    [System.IO.File]::WriteAllText($path, $json, $utf8NoBom)
}

function Get-UpdateManifestNotesAr([string] $appVersion) {
    $templatePath = Join-Path $PSScriptRoot "update_manifest_notes_ar.template.txt"
    $template = (Read-Utf8Text -path $templatePath).Trim()
    return $template -replace '\{0\}', $appVersion
}

$iscc = Ensure-InnoCompiler
Write-Host ">> Using ISCC: $iscc" -ForegroundColor Green

$signtool = Find-SignTool
if ($signtool) {
    Write-Host ">> Using SignTool: $signtool" -ForegroundColor Green
} else {
    Write-Host "!! SignTool not found (Windows SDK). Skipping code signing." -ForegroundColor Yellow
}

Write-Host ">> flutter pub get" -ForegroundColor Cyan
flutter pub get

Write-Host ">> flutter build windows --release" -ForegroundColor Cyan
flutter build windows --release

$releaseDir = Join-Path $appDir "build\windows\x64\runner\Release"
if (-not (Test-Path $releaseDir)) {
    throw "Release folder not found: $releaseDir"
}

$appExe = Join-Path $releaseDir "MizaPos.exe"
if ($signtool) {
    # Sign app binary BEFORE building installer so extracted files remain signed.
    Try-CodeSignFile -path $appExe -signTool $signtool | Out-Null

    # Also sign DLLs shipped with the app (reduces AV/SmartScreen warnings).
    Get-ChildItem -LiteralPath $releaseDir -File -Include *.dll, *.exe | ForEach-Object {
        Try-CodeSignFile -path $_.FullName -signTool $signtool | Out-Null
    }
}

$iss = Join-Path $root "installer\MizaPos.iss"
if (-not (Test-Path $iss)) {
    throw "Missing installer script: $iss"
}

$pubspec = Join-Path $appDir "pubspec.yaml"
$fullAppVersion = Get-FullAppVersionFromPubspec -pubspecPath $pubspec
$appVersion = Get-AppVersionFromPubspec -pubspecPath $pubspec
Write-Host ">> App version (from pubspec): $fullAppVersion (Inno label: $appVersion)" -ForegroundColor Green

$packagedExe = Join-Path $releaseDir "MizaPos.exe"
if (-not (Test-Path -LiteralPath $packagedExe)) {
    throw "Packaged binary missing before Inno compile: $packagedExe"
}
Write-Host ">> Packaging desktop build from: $releaseDir" -ForegroundColor Green

$dist = Join-Path $root "dist"
New-Item -ItemType Directory -Force -Path $dist | Out-Null

Write-Host ">> Compiling installer (Inno)..." -ForegroundColor Cyan
& $iscc "/DMyAppVersion=$appVersion" $iss
if ($LASTEXITCODE -ne 0) {
    throw "ISCC failed with exit code $LASTEXITCODE"
}

$setup = Join-Path $dist "MizaPos-Setup-$appVersion.exe"
if (-not (Test-Path $setup)) {
    throw "Expected output not found: $setup (check installer\MizaPos.iss OutputBaseFilename and MyAppVersion)"
}

if ($signtool) {
    # Sign the installer itself (improves SmartScreen + AV reputation).
    Try-CodeSignFile -path $setup -signTool $signtool | Out-Null
}

# Stable URL used by update-manifest.json (in-place upgrade keeps user data in %LOCALAPPDATA%\MizaPos\data).
$setupStable = Join-Path $dist "MizaPos-Setup.exe"
Copy-Item -LiteralPath $setup -Destination $setupStable -Force

# Keep manifest version as a quoted semver string (never a JSON number like 1.033).
$manifestPath = Join-Path $root "update-manifest.json"
$notesAr = Get-UpdateManifestNotesAr -appVersion $appVersion
$manifest = [ordered]@{
    version   = $fullAppVersion
    setup_url = "https://mizapos.com/download/MizaPos-Setup.exe"
    apk_url   = "https://mizapos.com/download/MizaPos-Android-app.apk"
    notes_ar  = $notesAr
    notes_en  = ('Version ' + $appVersion + ': modern voucher activation dialog, distributors hub UI, mobile account page, session identity panel, website pricing page, and general improvements.')
}
Write-Utf8Json -path $manifestPath -json ($manifest | ConvertTo-Json -Depth 4)
Copy-Item -LiteralPath $manifestPath -Destination (Join-Path $root "update_manifest.json") -Force
Write-Host ">> Wrote update manifest: $manifestPath (version=$fullAppVersion)" -ForegroundColor Green

Copy-Item -LiteralPath (Join-Path $root "docs\INSTALL_ONE_FILE_AR.txt") `
    -Destination (Join-Path $dist "INSTALL_ONE_FILE_AR.txt") -Force

$desktopDir = [Environment]::GetFolderPath("Desktop")
if ($desktopDir -and (Test-Path -LiteralPath $desktopDir)) {
    $desktopSetup = Join-Path $desktopDir "MizaPos-Setup-$appVersion.exe"
    Copy-Item -LiteralPath $setup -Destination $desktopSetup -Force
}

Write-Host ""
Write-Host "Installer ready (single file for users to download):" -ForegroundColor Green
Write-Host "  $setup"
Write-Host "  $setupStable (stable URL for in-app updates)"
if ($desktopDir -and (Test-Path -LiteralPath $desktopDir)) {
    Write-Host "  $(Join-Path $desktopDir "MizaPos-Setup-$appVersion.exe")"
}
Write-Host ""
Write-Host "Arabic explanation:" -ForegroundColor Cyan
Write-Host "  $(Join-Path $dist 'INSTALL_ONE_FILE_AR.txt')"
Write-Host "Done." -ForegroundColor Green

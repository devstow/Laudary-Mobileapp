<#
.SYNOPSIS
  Builds the signed, distributable Android release APKs of the Smart Wash app for one environment.

.DESCRIPTION
  1. Refuses to run without android/key.properties (release signing) - a debug-signed APK must never be distributed.
  2. Injects the environment's API URL from env/<Env>.json via --dart-define-from-file (the ONLY place it is set).
  3. Builds ONE UNIVERSAL APK (64-bit ARM + 32-bit ARM + x86_64) with Dart obfuscation + split debug info.
     A browser cannot tell which CPU a phone has, so the single file behind the Download button and the QR code
     must install on EVERY compatible device: the earlier per-ABI split served a 64-bit-only file that 32-bit
     Android phones (many budget / Android Go devices) reject with "App not installed" (2026-10-28).
  4. Re-signs each APK with apksigner so v1 + v2 + v3 signature schemes are ALL present (Gradle drops v1 for
     minSdk 24; some installers still want it), then VERIFIES: pinned release certificate, 16 KB zip alignment,
     application id and version, not debuggable, the expected native libraries.
  5. Optional early check: installs the APK on an attached device (adb). The AUTHORITATIVE, mandatory gate is in
     tool/publish_apk.ps1, which installs the file DOWNLOADED FROM STAGING before it is made public.
  6. Produces dist/<Env>/smartwash.apk (+ .json) - the file tool/publish_apk.ps1 uploads.

  Version code: a universal APK's versionCode is the pubspec build number itself. It must stay ABOVE every
  versionCode ever published (the old per-ABI builds used 1000+N / 2000+N, e.g. 2008), otherwise Android treats
  the update as a downgrade and shows "App not installed". The script enforces this.

  Version and build number come from pubspec.yaml ("version: 1.0.0+1"). Bump them there before every
  public release; Android only installs an update when the build number (+n) increases.

.EXAMPLE
  .\tool\build_release_apk.ps1                 # staging
  .\tool\build_release_apk.ps1 -Env production -PublicInfoUrl https://example.com/download/android/info
#>
[CmdletBinding()]
param(
    [ValidateNotNullOrEmpty()][string] $Env = 'staging',
    [string] $OutDir = '',
    # Where the landing page reports what it currently serves (/download/android/info). Used to refuse a
    # build whose number is not higher than the published one (Android would refuse to install it).
    [string] $PublicInfoUrl = '',
    [switch] $SkipServerCheck,
    # The adb install gate is mandatory when a device is attached; pass this to skip it deliberately.
    [switch] $SkipDeviceInstall
)
# 'Continue', not 'Stop': flutter/apksigner/aapt print warnings on stderr, which Windows PowerShell would otherwise
# turn into terminating errors. Every native call below checks $LASTEXITCODE and throws explicitly.
$ErrorActionPreference = 'Continue'
$root = Resolve-Path (Join-Path $PSScriptRoot '..')
Set-Location $root
if ($OutDir -eq '') { $OutDir = Join-Path $root "dist\$Env" }
if ($PublicInfoUrl -eq '' -and $Env -eq 'staging') { $PublicInfoUrl = 'https://smartwash-staging.20-203-96-110.nip.io/download/android/info' }

# --- preconditions -------------------------------------------------------------------------------
$envFile = Join-Path $root "env\$Env.json"
if (-not (Test-Path $envFile)) { throw "Missing $envFile (see env/README.md)." }
$envJson = Get-Content $envFile -Raw | ConvertFrom-Json
$apiUrl = [string]$envJson.API_BASE_URL
if (-not $apiUrl.StartsWith('https://')) { throw "env/$Env.json: API_BASE_URL must be an https:// URL for a release build (got '$apiUrl')." }

$keyProps = Join-Path $root 'android\key.properties'
if (-not (Test-Path $keyProps)) { throw "android/key.properties not found - release signing is required. See android/key.properties.example and RELEASE.md." }
$kp = @{}
Get-Content $keyProps | Where-Object { $_ -match '^\s*([^#=]+)=(.*)$' } | ForEach-Object { $kp[$Matches[1].Trim()] = $Matches[2].Trim() }
$storeFile = Join-Path $root "android\$($kp['storeFile'])"
if (-not (Test-Path $storeFile)) { throw "Keystore '$($kp['storeFile'])' named in key.properties does not exist." }
foreach ($k in 'storePassword', 'keyAlias', 'keyPassword') { if (-not $kp[$k]) { throw "key.properties is missing '$k'." } }

$pinFile = Join-Path $PSScriptRoot 'release-cert.sha256'
if (-not (Test-Path $pinFile)) { throw "tool/release-cert.sha256 missing - it pins the release certificate fingerprint (apksigner verify --print-certs)." }
$pin = ((Get-Content $pinFile -Raw) -replace '#[^\r\n]*', '' -replace '[^0-9a-fA-F]', '').ToLowerInvariant()
if ($pin.Length -ne 64) { throw 'tool/release-cert.sha256 must contain exactly one SHA-256 hex fingerprint.' }

$pubspec = Get-Content (Join-Path $root 'pubspec.yaml') -Raw
if ($pubspec -notmatch '(?m)^version:\s*(\d+\.\d+\.\d+)\+(\d+)\s*$') { throw 'pubspec.yaml: expected "version: x.y.z+n".' }
$version = $Matches[1]; $build = [int]$Matches[2]

$gradle = Get-Content (Join-Path $root 'android\app\build.gradle.kts') -Raw
$appId = if ($gradle -match 'applicationId\s*=\s*"([^"]+)"') { $Matches[1] } else { '?' }

# Android tooling (apksigner needs a JDK; Android Studio ships one).
$sdk = @($env:ANDROID_HOME, $env:ANDROID_SDK_ROOT, (Join-Path $env:LOCALAPPDATA 'Android\Sdk')) | Where-Object { $_ -and (Test-Path $_) } | Select-Object -First 1
if (-not $sdk) { throw 'Android SDK not found (set ANDROID_HOME).' }
$bt = Get-ChildItem (Join-Path $sdk 'build-tools') -Directory | Where-Object { Test-Path (Join-Path $_.FullName 'apksigner.bat') } | Sort-Object { [version]($_.Name -replace '[^0-9.].*$', '') } -Descending | Select-Object -First 1
if (-not $bt) { throw "No build-tools with apksigner under $sdk." }
$apksigner = Join-Path $bt.FullName 'apksigner.bat'; $aapt = Join-Path $bt.FullName 'aapt.exe'; $zipalign = Join-Path $bt.FullName 'zipalign.exe'
$adb = Join-Path $sdk 'platform-tools\adb.exe'
if (-not $env:JAVA_HOME -or -not (Test-Path (Join-Path $env:JAVA_HOME 'bin\java.exe'))) {
    $jbr = @("$env:ProgramFiles\Android\Android Studio\jbr", "$env:ProgramFiles\Android\Android Studio\jre") | Where-Object { Test-Path (Join-Path $_ 'bin\java.exe') } | Select-Object -First 1
    if (-not $jbr) { throw 'JAVA_HOME is not set and Android Studio''s JBR was not found - apksigner needs a JDK.' }
    $env:JAVA_HOME = $jbr
}

# Downgrade guard BEFORE the (slow) build: the number must be above what users can already download.
$live = $null
if (-not $SkipServerCheck -and $PublicInfoUrl) {
    try { $live = Invoke-RestMethod -Uri $PublicInfoUrl -TimeoutSec 20 -Headers @{ 'Cache-Control' = 'no-cache' } }
    catch { Write-Warning "Could not read $PublicInfoUrl ($($_.Exception.Message)); skipping the downgrade check." }
    if ($live -and $live.buildNumber) {
        # versionCode of what phones may have installed: per-ABI split builds were abiIndex*1000 + N.
        $liveAbi = [string]$live.abi
        $liveCode = [int]$live.buildNumber + $(switch ($liveAbi) { 'armeabi-v7a' { 1000 } 'arm64-v8a' { 2000 } 'x86_64' { 4000 } default { 0 } })
        foreach ($vv in @($live.variants)) {
            if ($vv -and $vv.buildNumber) { $c = [int]$vv.buildNumber + $(switch ([string]$vv.abi) { 'armeabi-v7a' { 1000 } 'arm64-v8a' { 2000 } 'x86_64' { 4000 } default { 0 } }); if ($c -gt $liveCode) { $liveCode = $c } }
        }
        if ($build -le $liveCode) {
            throw "Phones may already have versionCode $liveCode installed (live: $($live.versionLabel), $liveAbi). This build's versionCode would be $build - Android refuses a downgrade ('App not installed'). Set 'version: x.y.z+N' with N > $liveCode in pubspec.yaml."
        }
    }
}

Write-Host "Smart Wash Android release  env=$Env  version=$version+$build  appId=$appId" -ForegroundColor Cyan
Write-Host "API_BASE_URL = $apiUrl"
if ($live) { Write-Host "Landing page serves $($live.versionLabel) today; this build is newer." -ForegroundColor DarkGray }

# --- build ---------------------------------------------------------------------------------------
flutter pub get | Out-Host
if ($LASTEXITCODE -ne 0) { throw 'flutter pub get failed.' }
$symbols = Join-Path $root "build\symbols\$version+$build"
flutter build apk --release --target-platform android-arm,android-arm64,android-x64 --obfuscate "--split-debug-info=$symbols" "--dart-define-from-file=$envFile" | Out-Host
if ($LASTEXITCODE -ne 0) { throw 'flutter build apk failed.' }

# One universal file: every ABI a compatible phone (or Chromebook / emulator) can have.
$requiredAbis = @('arm64-v8a', 'armeabi-v7a', 'x86_64')
$variants = @(
    @{ Abi = 'universal'; Source = 'app-release.apk'; File = 'smartwash.apk'; Json = 'smartwash.json'; Primary = $true }
)
# Old per-ABI outputs must never be picked up by mistake.
Remove-Item (Join-Path $OutDir 'smartwash-armeabi-v7a.*') -ErrorAction SilentlyContinue
New-Item -ItemType Directory -Force $OutDir | Out-Null
$staging = Join-Path $root "build\release-signed"
New-Item -ItemType Directory -Force $staging | Out-Null
$env:SW_KS_PASS = $kp['storePassword']; $env:SW_KEY_PASS = $kp['keyPassword']
$results = @()
try {
    foreach ($v in $variants) {
        $src = Join-Path $root "build\app\outputs\flutter-apk\$($v.Source)"
        if (-not (Test-Path $src)) { throw "Expected APK not found: $src" }
        $signed = Join-Path $staging $v.File

        # --- sign with every scheme (v1 + v2 + v3) using the pinned release key; alignment is preserved ----------
        & $apksigner sign --ks $storeFile --ks-pass env:SW_KS_PASS --ks-key-alias $kp['keyAlias'] --key-pass env:SW_KEY_PASS `
            --v1-signing-enabled true --v2-signing-enabled true --v3-signing-enabled true --out $signed $src | Out-Host
        if ($LASTEXITCODE -ne 0) { throw "apksigner sign failed for $($v.Abi)." }

        # --- verify everything a phone checks before it says "App not installed" ---------------------------------
        # --min-sdk-version 23 makes apksigner evaluate the v1 (JAR) signature too; for a minSdk-24 APK it
        # otherwise skips v1 and reports "false" even though the signature is in the archive.
        $sig = & $apksigner verify --verbose --print-certs --min-sdk-version 23 $signed 2>&1 | Out-String
        if ($LASTEXITCODE -ne 0 -or $sig -notmatch '(?m)^Verifies') { throw "apksigner could not verify $($v.Abi):`n$sig" }
        foreach ($scheme in 'v1 scheme \(JAR signing\): true', 'Scheme v2\): true', 'Scheme v3\): true') { if ($sig -notmatch $scheme) { throw "$($v.Abi): signature scheme missing ($scheme):`n$sig" } }
        $signers = [regex]::Matches($sig, 'Signer #\d+ certificate SHA-256 digest: ([0-9a-f]{64})')
        if ($signers.Count -ne 1) { throw "$($v.Abi): expected exactly one signer, found $($signers.Count)." }
        $certSha = $signers[0].Groups[1].Value
        if ($certSha -ne $pin) { throw "$($v.Abi) is signed with the WRONG certificate ($certSha); expected the release key $pin (tool/release-cert.sha256)." }
        & $zipalign -c -P 16 4 $signed | Out-Null
        if ($LASTEXITCODE -ne 0) { throw "$($v.Abi): not 16 KB page aligned (zipalign -c -P 16 failed)." }

        $badging = & $aapt dump badging $signed 2>&1 | Out-String
        if ($badging -notmatch "package: name='([^']+)' versionCode='(\d+)' versionName='([^']+)'") { throw "aapt could not read the manifest of $($v.Abi):`n$badging" }
        $pkg = $Matches[1]; $code = [int]$Matches[2]; $name = $Matches[3]
        if ($pkg -ne $appId) { throw "APK package '$pkg' != build.gradle.kts applicationId '$appId'." }
        if ($name -ne $version) { throw "APK versionName $name != pubspec $version." }
        if ($code -ne $build) { throw "APK versionCode $code != pubspec build number $build (stale build output?)." }
        if ($badging -match 'application-debuggable' -or $badging -match "testOnly='-1'") { throw 'APK is debuggable/testOnly - this is not a distributable release build.' }
        if ($badging -notmatch "native-code:(.*)") { throw "$($v.Abi): APK has no native libraries." }
        $abis = @([regex]::Matches($Matches[1], "'([^']+)'") | ForEach-Object { $_.Groups[1].Value })
        foreach ($need in $requiredAbis) { if ($abis -notcontains $need) { throw "Universal APK lacks $need libraries (has: $($abis -join ', ')) - it would not install on those phones." } }
        $minSdk = if ($badging -match "sdkVersion:'(\d+)'") { [int]$Matches[1] } else { 0 }
        $targetSdk = if ($badging -match "targetSdkVersion:'(\d+)'") { [int]$Matches[1] } else { 0 }
        Write-Host "Verified $($v.Abi): v1+v2+v3, release cert $($certSha.Substring(0, 16))..., $pkg $name ($code), minSdk $minSdk, targetSdk $targetSdk, $([math]::Round((Get-Item $signed).Length / 1MB, 1)) MB" -ForegroundColor Green

        $results += [pscustomobject]@{ Variant = $v; Signed = $signed; Cert = $certSha; Abis = $abis; MinSdk = $minSdk; TargetSdk = $targetSdk; VersionCode = $code }
    }
}
finally { Remove-Item Env:SW_KS_PASS -ErrorAction SilentlyContinue; Remove-Item Env:SW_KEY_PASS -ErrorAction SilentlyContinue }

# --- install gate: put the primary APK on an attached device/emulator exactly as a phone would -------------
if (-not $SkipDeviceInstall) {
    $devices = @()
    if (Test-Path $adb) { $devices = @(& $adb devices 2>$null | Select-Object -Skip 1 | Where-Object { $_ -match '^\S+\s+device$' } | ForEach-Object { ($_ -split '\s+')[0] }) }
    if ($devices.Count -eq 0) {
        Write-Warning 'No Android device or emulator attached (adb devices) - the on-device install check was skipped. Start an emulator or plug in a phone to run it.'
    } else {
        $serial = $devices[0]
        $abilist = (& $adb -s $serial shell getprop ro.product.cpu.abilist 2>$null | Out-String).Trim()
        $pick = $results | Select-Object -First 1
        if (-not $pick) {
            Write-Warning "Device $serial ($abilist) runs neither ARM ABI; install check skipped."
        } else {
            $wasInstalled = ((& $adb -s $serial shell pm list packages $appId 2>$null | Out-String) -match "package:$([regex]::Escape($appId))(\s|$)")
            Write-Host "Installing $($pick.Variant.Abi) build on $serial ($abilist)..." -ForegroundColor Cyan
            $out = & $adb -s $serial install -r $pick.Signed 2>&1 | Out-String
            if ($LASTEXITCODE -ne 0 -or $out -notmatch 'Success') { throw "adb install FAILED on $serial - this is what a phone would show as 'App not installed':`n$out" }
            $listed = (& $adb -s $serial shell pm list packages $appId 2>$null | Out-String) -match "package:$([regex]::Escape($appId))(\s|$)"
            if (-not $listed) { throw "adb reported success but $appId is not installed on $serial." }
            Write-Host "Installed and verified on $serial." -ForegroundColor Green
            if (-not $wasInstalled) { & $adb -s $serial uninstall $appId | Out-Null }
        }
    }
}

# --- package for publishing ----------------------------------------------------------------------
foreach ($r in $results) {
    $v = $r.Variant
    $target = Join-Path $OutDir $v.File
    Copy-Item $r.Signed $target -Force
    $size = (Get-Item $target).Length
    $sha = (Get-FileHash $target -Algorithm SHA256).Hash.ToLowerInvariant()
    $info = [ordered]@{
        fileName      = $v.File
        version       = $version
        buildNumber   = $build
        versionCode   = $r.VersionCode
        applicationId = $appId
        environment   = $Env
        apiBaseUrl    = $apiUrl
        abi           = $v.Abi
        abis          = $r.Abis
        sizeBytes     = $size
        sha256        = $sha
        certSha256    = $r.Cert
        signatureSchemes = @('v1', 'v2', 'v3')
        minSdk        = $r.MinSdk
        targetSdk     = $r.TargetSdk
        builtAtUtc    = (Get-Date).ToUniversalTime().ToString('o')
    }
    [IO.File]::WriteAllText((Join-Path $OutDir $v.Json), ($info | ConvertTo-Json), (New-Object System.Text.UTF8Encoding $false))  # no BOM
    Write-Host ''
    Write-Host "APK : $target  ($([math]::Round($size / 1MB, 1)) MB, $($v.Abi))" -ForegroundColor Green
    Write-Host "SHA : $sha"
}
Write-Host "Symbols: $symbols (keep for crash de-obfuscation)"
Write-Host "Next: .\tool\publish_apk.ps1 -Env $Env -SshKey <path-to-key.pem>"

<#
.SYNOPSIS
  Builds the signed, distributable Android release APK of the Smart Wash app for one environment.

.DESCRIPTION
  1. Refuses to run without android/key.properties (release signing) - a debug-signed APK must never be distributed.
  2. Injects the environment's API URL from env/<Env>.json via --dart-define-from-file (the ONLY place it is set).
  3. Builds ARM-only (android-arm + android-arm64): real phones never need x86_64, and a smaller file
     downloads reliably on mobile data (a cut-short download shows up as "App not installed").
  4. VERIFIES the result before it can be published: signed with the pinned release certificate
     (tool/release-cert.sha256, v2/v3 schemes), correct application id and version, not debuggable,
     ARM libraries present, and a build number above what the landing page already serves.
  5. Produces dist/<Env>/smartwash.apk plus dist/<Env>/smartwash.json (version, build number, size, SHA-256,
     certificate) - the pair that tool/publish_apk.ps1 uploads and that the SaaS landing page reads.

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
    [switch] $SkipServerCheck
)
$ErrorActionPreference = 'Stop'
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
$storeFile = ((Get-Content $keyProps) | Where-Object { $_ -match '^storeFile=' }) -replace '^storeFile=', ''
if (-not (Test-Path (Join-Path $root "android\$storeFile"))) { throw "Keystore '$storeFile' named in key.properties does not exist." }

$pinFile = Join-Path $PSScriptRoot 'release-cert.sha256'
if (-not (Test-Path $pinFile)) { throw "tool/release-cert.sha256 missing - it pins the release certificate fingerprint (apksigner verify --print-certs)." }
$pin = ((Get-Content $pinFile -Raw) -replace '#[^\r\n]*', '' -replace '[^0-9a-fA-F]', '').ToLowerInvariant()
if ($pin.Length -ne 64) { throw 'tool/release-cert.sha256 must contain exactly one SHA-256 hex fingerprint.' }

$pubspec = Get-Content (Join-Path $root 'pubspec.yaml') -Raw
if ($pubspec -notmatch '(?m)^version:\s*(\d+\.\d+\.\d+)\+(\d+)\s*$') { throw 'pubspec.yaml: expected "version: x.y.z+n".' }
$version = $Matches[1]; $build = [int]$Matches[2]

$gradle = Get-Content (Join-Path $root 'android\app\build.gradle.kts') -Raw
$appId = if ($gradle -match 'applicationId\s*=\s*"([^"]+)"') { $Matches[1] } else { '?' }

# Android tooling for the post-build checks (apksigner needs a JDK; Android Studio ships one).
$sdk = @($env:ANDROID_HOME, $env:ANDROID_SDK_ROOT, (Join-Path $env:LOCALAPPDATA 'Android\Sdk')) | Where-Object { $_ -and (Test-Path $_) } | Select-Object -First 1
if (-not $sdk) { throw 'Android SDK not found (set ANDROID_HOME).' }
$bt = Get-ChildItem (Join-Path $sdk 'build-tools') -Directory | Where-Object { Test-Path (Join-Path $_.FullName 'apksigner.bat') } | Sort-Object { [version]($_.Name -replace '[^0-9.].*$', '') } -Descending | Select-Object -First 1
if (-not $bt) { throw "No build-tools with apksigner under $sdk." }
if (-not $env:JAVA_HOME -or -not (Test-Path (Join-Path $env:JAVA_HOME 'bin\java.exe'))) {
    $jbr = @("$env:ProgramFiles\Android\Android Studio\jbr", "$env:ProgramFiles\Android\Android Studio\jre") | Where-Object { Test-Path (Join-Path $_ 'bin\java.exe') } | Select-Object -First 1
    if (-not $jbr) { throw 'JAVA_HOME is not set and Android Studio''s JBR was not found - apksigner needs a JDK.' }
    $env:JAVA_HOME = $jbr
}

# Downgrade guard BEFORE the (slow) build: the number must be above what users can already download.
$live = $null
if (-not $SkipServerCheck -and $PublicInfoUrl) {
    try {
        $live = Invoke-RestMethod -Uri $PublicInfoUrl -TimeoutSec 20 -Headers @{ 'Cache-Control' = 'no-cache' }
    } catch {
        Write-Warning "Could not read $PublicInfoUrl ($($_.Exception.Message)); skipping the downgrade check."
    }
    if ($live -and $live.buildNumber -and [int]$live.buildNumber -ge $build) {
        throw "The landing page already serves build $($live.buildNumber) ($($live.version)). Android refuses to install build $build over it - bump 'version: x.y.z+N' in pubspec.yaml and rebuild."
    }
}

Write-Host "Smart Wash Android release  env=$Env  version=$version+$build  appId=$appId" -ForegroundColor Cyan
Write-Host "API_BASE_URL = $apiUrl"
if ($live) { Write-Host "Landing page serves $($live.versionLabel) today; this build is newer." -ForegroundColor DarkGray }

# --- build ---------------------------------------------------------------------------------------
flutter pub get | Out-Host
if ($LASTEXITCODE -ne 0) { throw 'flutter pub get failed.' }
flutter build apk --release --target-platform android-arm,android-arm64 "--dart-define-from-file=$envFile" | Out-Host
if ($LASTEXITCODE -ne 0) { throw 'flutter build apk failed.' }

$apk = Join-Path $root 'build\app\outputs\flutter-apk\app-release.apk'
if (-not (Test-Path $apk)) { throw "Expected APK not found: $apk" }

# --- verify the build (everything a phone checks before it says "App not installed") ------------------
$sig = & (Join-Path $bt.FullName 'apksigner.bat') verify --verbose --print-certs $apk 2>&1 | Out-String
if ($LASTEXITCODE -ne 0 -or $sig -notmatch '(?m)^Verifies') { throw "apksigner could not verify the APK signature:`n$sig" }
if ($sig -notmatch 'Scheme v2\): true' -and $sig -notmatch 'Scheme v3\): true') { throw "APK is not v2/v3 signed:`n$sig" }
$signers = [regex]::Matches($sig, 'Signer #\d+ certificate SHA-256 digest: ([0-9a-f]{64})')
if ($signers.Count -ne 1) { throw "Expected exactly one signer, found $($signers.Count):`n$sig" }
$certSha = $signers[0].Groups[1].Value
if ($certSha -ne $pin) { throw "APK is signed with the WRONG certificate ($certSha). Expected the release key $pin (tool/release-cert.sha256). Check android/key.properties - this build must not be published." }

$badging = & (Join-Path $bt.FullName 'aapt.exe') dump badging $apk 2>&1 | Out-String
if ($badging -notmatch "package: name='([^']+)' versionCode='(\d+)' versionName='([^']+)'") { throw "aapt could not read the APK manifest:`n$badging" }
$pkg = $Matches[1]; $code = [int]$Matches[2]; $name = $Matches[3]
if ($pkg -ne $appId) { throw "APK package '$pkg' != build.gradle.kts applicationId '$appId'." }
if ($code -ne $build -or $name -ne $version) { throw "APK version $name+$code != pubspec $version+$build (stale build output?)." }
if ($badging -match 'application-debuggable' -or $badging -match "testOnly='-1'") { throw 'APK is debuggable/testOnly - this is not a distributable release build.' }
if ($badging -notmatch "native-code:(.*)") { throw 'APK has no native libraries.' }
$abis = @([regex]::Matches($Matches[1], "'([^']+)'") | ForEach-Object { $_.Groups[1].Value })
foreach ($need in 'arm64-v8a', 'armeabi-v7a') { if ($abis -notcontains $need) { throw "APK lacks $need libraries (has: $($abis -join ', '))." } }
$minSdk = if ($badging -match "sdkVersion:'(\d+)'") { [int]$Matches[1] } else { 0 }
$targetSdk = if ($badging -match "targetSdkVersion:'(\d+)'") { [int]$Matches[1] } else { 0 }
Write-Host "Verified: release certificate $($certSha.Substring(0, 16))..., $pkg $name ($code), abis $($abis -join '/'), minSdk $minSdk, targetSdk $targetSdk" -ForegroundColor Green

# --- package for publishing ----------------------------------------------------------------------
New-Item -ItemType Directory -Force $OutDir | Out-Null
$target = Join-Path $OutDir 'smartwash.apk'
Copy-Item $apk $target -Force
$size = (Get-Item $target).Length
$sha = (Get-FileHash $target -Algorithm SHA256).Hash.ToLowerInvariant()
$info = [ordered]@{
    fileName      = 'smartwash.apk'
    version       = $version
    buildNumber   = $build
    applicationId = $appId
    environment   = $Env
    apiBaseUrl    = $apiUrl
    sizeBytes     = $size
    sha256        = $sha
    certSha256    = $certSha
    abis          = $abis
    minSdk        = $minSdk
    targetSdk     = $targetSdk
    builtAtUtc    = (Get-Date).ToUniversalTime().ToString('o')
}
[IO.File]::WriteAllText((Join-Path $OutDir 'smartwash.json'), ($info | ConvertTo-Json), (New-Object System.Text.UTF8Encoding $false))  # no BOM

Write-Host ''
Write-Host "APK : $target  ($([math]::Round($size / 1MB, 1)) MB)" -ForegroundColor Green
Write-Host "SHA : $sha"
Write-Host "Info: $(Join-Path $OutDir 'smartwash.json')"
Write-Host "Next: .\tool\publish_apk.ps1 -Env $Env -SshKey <path-to-key.pem>"

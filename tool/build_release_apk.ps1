<#
.SYNOPSIS
  Builds the signed, distributable Android release APK of the Smart Wash app for one environment.

.DESCRIPTION
  1. Refuses to run without android/key.properties (release signing) - a debug-signed APK must never be distributed.
  2. Injects the environment's API URL from env/<Env>.json via --dart-define-from-file (the ONLY place it is set).
  3. Produces dist/<Env>/smartwash.apk plus dist/<Env>/smartwash.json (version, build number, size, SHA-256) -
     the pair that tool/publish_apk.ps1 uploads and that the SaaS landing page reads.

  Version and build number come from pubspec.yaml ("version: 1.0.0+1"). Bump them there before every
  public release; Android only installs an update when the build number (+n) increases.

.EXAMPLE
  .\tool\build_release_apk.ps1                 # staging
  .\tool\build_release_apk.ps1 -Env production
#>
[CmdletBinding()]
param(
    [ValidateNotNullOrEmpty()][string] $Env = 'staging',
    [string] $OutDir = ''
)
$ErrorActionPreference = 'Stop'
$root = Resolve-Path (Join-Path $PSScriptRoot '..')
Set-Location $root
if ($OutDir -eq '') { $OutDir = Join-Path $root "dist\$Env" }

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

$pubspec = Get-Content (Join-Path $root 'pubspec.yaml') -Raw
if ($pubspec -notmatch '(?m)^version:\s*(\d+\.\d+\.\d+)\+(\d+)\s*$') { throw 'pubspec.yaml: expected "version: x.y.z+n".' }
$version = $Matches[1]; $build = [int]$Matches[2]

$gradle = Get-Content (Join-Path $root 'android\app\build.gradle.kts') -Raw
$appId = if ($gradle -match 'applicationId\s*=\s*"([^"]+)"') { $Matches[1] } else { '?' }

Write-Host "Smart Wash Android release  env=$Env  version=$version+$build  appId=$appId" -ForegroundColor Cyan
Write-Host "API_BASE_URL = $apiUrl"

# --- build ---------------------------------------------------------------------------------------
flutter pub get | Out-Host
if ($LASTEXITCODE -ne 0) { throw 'flutter pub get failed.' }
flutter build apk --release "--dart-define-from-file=$envFile" | Out-Host
if ($LASTEXITCODE -ne 0) { throw 'flutter build apk failed.' }

$apk = Join-Path $root 'build\app\outputs\flutter-apk\app-release.apk'
if (-not (Test-Path $apk)) { throw "Expected APK not found: $apk" }

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
    builtAtUtc    = (Get-Date).ToUniversalTime().ToString('o')
}
[IO.File]::WriteAllText((Join-Path $OutDir 'smartwash.json'), ($info | ConvertTo-Json), (New-Object System.Text.UTF8Encoding $false))  # no BOM

Write-Host ''
Write-Host "APK : $target  ($([math]::Round($size / 1MB, 1)) MB)" -ForegroundColor Green
Write-Host "SHA : $sha"
Write-Host "Info: $(Join-Path $OutDir 'smartwash.json')"
Write-Host "Next: .\tool\publish_apk.ps1 -Env $Env -SshKey <path-to-key.pem>"

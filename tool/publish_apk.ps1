<#
.SYNOPSIS
  Uploads the APK built by build_release_apk.ps1 to the SaaS server so the landing page serves it.

.DESCRIPTION
  Copies dist/<Env>/smartwash.apk + smartwash.json to the server's download folder (SmartWash.Web's
  "Storage:DownloadsPath" + /android). The web app serves the file at <web-url>/download/android and reads
  smartwash.json for the version shown on the landing page - no restart needed, the next request picks
  up the new file. Replacing a release = run build_release_apk.ps1 then this script again.

  Guards (each one has produced an "App not installed" on a phone before):
    - refuses a build whose manifest lacks the release-certificate fingerprint or whose fingerprint differs
      from tool/release-cert.sha256 (wrong/debug key => Android will not install it over the existing app);
    - refuses a build number that is not above the one the landing page already serves (downgrade);
    - verifies the upload's SHA-256 on the server before swapping it in;
    - after the swap, downloads the public file in full and compares its SHA-256 with the local build, and
      checks /download/android/info reports the new build - what users get is exactly what was built.

.EXAMPLE
  .\tool\publish_apk.ps1 -SshKey D:\Source\Server-Prod\Sahala_key.pem
#>
[CmdletBinding()]
param(
    [string] $Env = 'staging',
    [Parameter(Mandatory = $true)][string] $SshKey,
    [string] $Target = 'azureuser@20.203.96.110',
    [string] $RemoteDir = '/opt/Staging/SmartWash/data/downloads/android',
    [string] $ServiceUser = 'smartwash',
    [string] $PublicUrl = 'https://smartwash-staging.20-203-96-110.nip.io/download/android'
)
$ErrorActionPreference = 'Stop'
$root = Resolve-Path (Join-Path $PSScriptRoot '..')
$dist = Join-Path $root "dist\$Env"
$apk = Join-Path $dist 'smartwash.apk'
$json = Join-Path $dist 'smartwash.json'
if (-not (Test-Path $apk) -or -not (Test-Path $json)) { throw "Build first: .\tool\build_release_apk.ps1 -Env $Env (missing $dist\smartwash.apk / .json)." }
$info = Get-Content $json -Raw | ConvertFrom-Json
$stamp = Get-Date -Format 'yyyyMMddHHmmss'
$parentDir = $RemoteDir.Substring(0, $RemoteDir.LastIndexOf('/'))
$infoUrl = "$PublicUrl/info"

# --- pre-flight: the file on disk is the file the manifest describes, signed with the release key ------
$localSha = (Get-FileHash $apk -Algorithm SHA256).Hash.ToLowerInvariant()
if ($localSha -ne $info.sha256) { throw "dist\$Env\smartwash.apk ($localSha) does not match smartwash.json ($($info.sha256)) - rebuild." }
$pinFile = Join-Path $PSScriptRoot 'release-cert.sha256'
if (-not (Test-Path $pinFile)) { throw 'tool/release-cert.sha256 missing (release certificate pin).' }
$pin = ((Get-Content $pinFile -Raw) -replace '#[^\r\n]*', '' -replace '[^0-9a-fA-F]', '').ToLowerInvariant()
if (-not $info.certSha256) { throw 'smartwash.json has no certSha256 - rebuild with the current build_release_apk.ps1 (it verifies the signature).' }
if ($info.certSha256 -ne $pin) { throw "Build is signed with certificate $($info.certSha256), not the release key $pin - refusing to publish." }
$live = $null
try { $live = Invoke-RestMethod -Uri $infoUrl -TimeoutSec 20 -Headers @{ 'Cache-Control' = 'no-cache' } }
catch { Write-Warning "Could not read $infoUrl ($($_.Exception.Message)) - continuing without the downgrade check." }
if ($live -and $live.buildNumber -and [int]$live.buildNumber -ge [int]$info.buildNumber) {
    throw "Landing page already serves build $($live.buildNumber); build $($info.buildNumber) would not install over it. Bump pubspec.yaml and rebuild."
}

Write-Host "Publishing Smart Wash $($info.version)+$($info.buildNumber) ($([math]::Round($info.sizeBytes / 1MB, 1)) MB, cert $($pin.Substring(0, 16))...) to ${Target}:$RemoteDir" -ForegroundColor Cyan
scp -i $SshKey -o IdentitiesOnly=yes $apk "${Target}:/tmp/smartwash-$stamp.apk"
if ($LASTEXITCODE -ne 0) { throw 'scp (apk) failed.' }
scp -i $SshKey -o IdentitiesOnly=yes $json "${Target}:/tmp/smartwash-$stamp.json"
if ($LASTEXITCODE -ne 0) { throw 'scp (json) failed.' }

# Verify the upload, install the new pair owned by the service user, swap it in (manifest first so the
# web app never pairs the new APK with the old manifest), then show what the server holds.
$lines = @(
    'set -e',
    "test `"`$(sha256sum /tmp/smartwash-$stamp.apk | cut -d' ' -f1)`" = '$localSha' || { echo 'upload corrupted (sha256 mismatch)'; exit 1; }",
    "sudo mkdir -p '$RemoteDir'",
    "sudo install -o $ServiceUser -g $ServiceUser -m 640 /tmp/smartwash-$stamp.apk '$RemoteDir/smartwash.apk.new'",
    "sudo install -o $ServiceUser -g $ServiceUser -m 640 /tmp/smartwash-$stamp.json '$RemoteDir/smartwash.json.new'",
    "sudo mv -f '$RemoteDir/smartwash.json.new' '$RemoteDir/smartwash.json'",
    "sudo mv -f '$RemoteDir/smartwash.apk.new' '$RemoteDir/smartwash.apk'",
    "sudo chown ${ServiceUser}:$ServiceUser '$parentDir' '$RemoteDir'",
    "sudo chmod 750 '$parentDir' '$RemoteDir'",
    "rm -f /tmp/smartwash-$stamp.apk /tmp/smartwash-$stamp.json",
    "echo `"server sha256: `$(sudo sha256sum '$RemoteDir/smartwash.apk' | cut -d' ' -f1)`""
)
# The commands go over stdin ("bash -s") so no quoting is lost between PowerShell, ssh and bash.
($lines -join "`n") | ssh -i $SshKey -o IdentitiesOnly=yes $Target 'bash -s'
if ($LASTEXITCODE -ne 0) { throw 'remote install failed.' }

# --- post-flight: what the public URL hands out is byte-for-byte this build -----------------------------
$tmp = Join-Path ([IO.Path]::GetTempPath()) "smartwash-public-$stamp.apk"
try {
    & curl.exe -sS -L --fail -o $tmp -w "public       : %{http_code} %{content_type} %{size_download} bytes in %{time_total}s`n" $PublicUrl
    if ($LASTEXITCODE -ne 0) { throw "public download failed (curl exit $LASTEXITCODE)." }
    $publicSha = (Get-FileHash $tmp -Algorithm SHA256).Hash.ToLowerInvariant()
    if ($publicSha -ne $localSha) { throw "PUBLIC DOWNLOAD DIFFERS from the build (public $publicSha, local $localSha) - users would get a broken file." }
    $served = Invoke-RestMethod -Uri $infoUrl -TimeoutSec 20 -Headers @{ 'Cache-Control' = 'no-cache' }
    if ([int]$served.buildNumber -ne [int]$info.buildNumber -or $served.sha256 -ne $localSha) { throw "/info still reports build $($served.buildNumber) sha $($served.sha256)." }
    Write-Host "public sha256: $publicSha (matches the build)   served as: $($served.fileName)"
} finally {
    Remove-Item $tmp -Force -ErrorAction SilentlyContinue
}
Write-Host "local  sha256: $localSha"
Write-Host "Download URL : $PublicUrl" -ForegroundColor Green

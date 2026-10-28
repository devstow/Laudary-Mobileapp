<#
.SYNOPSIS
  Uploads the APKs built by build_release_apk.ps1 to the SaaS server so the landing page serves them.

.DESCRIPTION
  Copies dist/<Env>/smartwash.apk (+ .json) and, when present, dist/<Env>/smartwash-armeabi-v7a.apk (+ .json) to
  the server's download folder (SmartWash.Web's "Storage:DownloadsPath" + /android). The web app serves the files
  at <web-url>/download/android (and ?abi=armeabi-v7a) and reads the json for the version shown on the landing
  page - no restart needed, the next request picks up the new files. Replacing a release = run
  build_release_apk.ps1 then this script again.

  Guards (each one has produced an "App not installed" on a phone before):
    - refuses a build whose manifest lacks the release-certificate fingerprint, whose fingerprint differs from
      tool/release-cert.sha256, or that lacks the v1+v2+v3 signature schemes;
    - refuses a build number that is not above the one the landing page already serves (downgrade);
    - verifies every upload's SHA-256 on the server before swapping it in;
    - after the swap, downloads each public file in full and compares its SHA-256 with the local build, and
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
$infoUrl = "$PublicUrl/info"
$parentDir = $RemoteDir.Substring(0, $RemoteDir.LastIndexOf('/'))
$stamp = Get-Date -Format 'yyyyMMddHHmmss'

$pinFile = Join-Path $PSScriptRoot 'release-cert.sha256'
if (-not (Test-Path $pinFile)) { throw 'tool/release-cert.sha256 missing (release certificate pin).' }
$pin = ((Get-Content $pinFile -Raw) -replace '#[^\r\n]*', '' -replace '[^0-9a-fA-F]', '').ToLowerInvariant()

# --- pre-flight: every file on disk is the file its manifest describes, signed with the release key ---------
$variants = @(
    @{ File = 'smartwash.apk';              Json = 'smartwash.json';              Url = $PublicUrl;                      Required = $true },
    @{ File = 'smartwash-armeabi-v7a.apk'; Json = 'smartwash-armeabi-v7a.json'; Url = "$PublicUrl?abi=armeabi-v7a"; Required = $false }
)
$items = @()
foreach ($v in $variants) {
    $apk = Join-Path $dist $v.File; $json = Join-Path $dist $v.Json
    if (-not (Test-Path $apk) -or -not (Test-Path $json)) {
        if ($v.Required) { throw "Build first: .\tool\build_release_apk.ps1 -Env $Env (missing $apk / .json)." }
        Write-Host "No $($v.File) in dist - the 32-bit variant will not be published." -ForegroundColor DarkGray; continue
    }
    $info = Get-Content $json -Raw | ConvertFrom-Json
    $sha = (Get-FileHash $apk -Algorithm SHA256).Hash.ToLowerInvariant()
    if ($sha -ne $info.sha256) { throw "$($v.File) ($sha) does not match its json ($($info.sha256)) - rebuild." }
    if (-not $info.certSha256) { throw "$($v.Json) has no certSha256 - rebuild with the current build_release_apk.ps1 (it verifies the signature)." }
    if ($info.certSha256 -ne $pin) { throw "$($v.File) is signed with certificate $($info.certSha256), not the release key $pin - refusing to publish." }
    if (-not $info.signatureSchemes -or @($info.signatureSchemes).Count -lt 3) { throw "$($v.File) was not signed with v1+v2+v3 - rebuild with the current build script." }
    $items += [pscustomobject]@{ V = $v; Apk = $apk; Json = $json; Info = $info; Sha = $sha }
}
$primary = $items[0].Info
$live = $null
try { $live = Invoke-RestMethod -Uri $infoUrl -TimeoutSec 20 -Headers @{ 'Cache-Control' = 'no-cache' } }
catch { Write-Warning "Could not read $infoUrl ($($_.Exception.Message)) - continuing without the downgrade check." }
if ($live -and $live.buildNumber -and [int]$live.buildNumber -ge [int]$primary.buildNumber) {
    throw "Landing page already serves build $($live.buildNumber); build $($primary.buildNumber) would not install over it. Bump pubspec.yaml and rebuild."
}

Write-Host "Publishing Smart Wash $($primary.version)+$($primary.buildNumber) ($($items.Count) file(s), cert $($pin.Substring(0, 16))...) to ${Target}:$RemoteDir" -ForegroundColor Cyan
foreach ($i in $items) {
    scp -i $SshKey -o IdentitiesOnly=yes $i.Apk "${Target}:/tmp/$($i.V.File).$stamp"
    if ($LASTEXITCODE -ne 0) { throw "scp ($($i.V.File)) failed." }
    scp -i $SshKey -o IdentitiesOnly=yes $i.Json "${Target}:/tmp/$($i.V.Json).$stamp"
    if ($LASTEXITCODE -ne 0) { throw "scp ($($i.V.Json)) failed." }
}

# Verify each upload, install the pairs owned by the service user, swap them in (json first so the web app never
# pairs a new APK with the old manifest), remove a stale 32-bit file when none was published, then report.
$lines = @('set -e', "sudo mkdir -p '$RemoteDir'")
foreach ($i in $items) {
    $f = $i.V.File; $j = $i.V.Json
    $lines += "test `"`$(sha256sum /tmp/$f.$stamp | cut -d' ' -f1)`" = '$($i.Sha)' || { echo 'upload corrupted ($f)'; exit 1; }"
    $lines += "sudo install -o $ServiceUser -g $ServiceUser -m 640 /tmp/$f.$stamp '$RemoteDir/$f.new'"
    $lines += "sudo install -o $ServiceUser -g $ServiceUser -m 640 /tmp/$j.$stamp '$RemoteDir/$j.new'"
    $lines += "sudo mv -f '$RemoteDir/$j.new' '$RemoteDir/$j'"
    $lines += "sudo mv -f '$RemoteDir/$f.new' '$RemoteDir/$f'"
    $lines += "rm -f /tmp/$f.$stamp /tmp/$j.$stamp"
}
if (-not ($items | Where-Object { $_.V.File -eq 'smartwash-armeabi-v7a.apk' })) {
    $lines += "sudo rm -f '$RemoteDir/smartwash-armeabi-v7a.apk' '$RemoteDir/smartwash-armeabi-v7a.json'"
}
$lines += "sudo chown ${ServiceUser}:$ServiceUser '$parentDir' '$RemoteDir'"
$lines += "sudo chmod 750 '$parentDir' '$RemoteDir'"
$lines += "sudo ls -la '$RemoteDir'"
$lines += 'true # last line: PowerShell appends a CR to piped stdin, the comment absorbs it'
# The commands go over stdin ("bash -s") so no quoting is lost between PowerShell, ssh and bash.
($lines -join "`n") | ssh -i $SshKey -o IdentitiesOnly=yes $Target 'bash -s'
if ($LASTEXITCODE -ne 0) { throw 'remote install failed.' }

# --- post-flight: what the public URLs hand out is byte-for-byte what was built ----------------------------
foreach ($i in $items) {
    $tmp = Join-Path ([IO.Path]::GetTempPath()) "smartwash-public-$stamp-$($i.V.File)"
    try {
        & curl.exe -sS -L --fail -o $tmp -w "public ($($i.V.File)): %{http_code} %{content_type} %{size_download} bytes in %{time_total}s`n" $i.V.Url
        if ($LASTEXITCODE -ne 0) { throw "public download failed for $($i.V.File) (curl exit $LASTEXITCODE)." }
        $publicSha = (Get-FileHash $tmp -Algorithm SHA256).Hash.ToLowerInvariant()
        if ($publicSha -ne $i.Sha) { throw "PUBLIC DOWNLOAD DIFFERS from the build for $($i.V.File) (public $publicSha, local $($i.Sha)) - users would get a broken file." }
    } finally { Remove-Item $tmp -Force -ErrorAction SilentlyContinue }
}
$served = Invoke-RestMethod -Uri $infoUrl -TimeoutSec 20 -Headers @{ 'Cache-Control' = 'no-cache' }
if ([int]$served.buildNumber -ne [int]$primary.buildNumber -or $served.sha256 -ne $items[0].Sha) { throw "/info still reports build $($served.buildNumber) sha $($served.sha256)." }
Write-Host "Served as $($served.fileName); variants: $(($served.variants | ForEach-Object { "$($_.abi)=$([math]::Round($_.sizeBytes / 1MB, 1)) MB" }) -join ', ')" -ForegroundColor Green
Write-Host "Download URL : $PublicUrl" -ForegroundColor Green

<#
.SYNOPSIS
  Uploads the APK built by build_release_apk.ps1 to the SaaS server so the landing page serves it.

.DESCRIPTION
  Copies dist/<Env>/smartwash.apk + smartwash.json to the server's download folder (SmartWash.Web's
  "Storage:DownloadsPath" + /android). The web app serves the file at <web-url>/download/android and reads
  smartwash.json for the version shown on the landing page - no restart needed, the next request picks
  up the new file. Replacing a release = run build_release_apk.ps1 then this script again.

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

Write-Host "Publishing Smart Wash $($info.version)+$($info.buildNumber) ($([math]::Round($info.sizeBytes / 1MB, 1)) MB) to ${Target}:$RemoteDir" -ForegroundColor Cyan
scp -i $SshKey -o IdentitiesOnly=yes $apk "${Target}:/tmp/smartwash-$stamp.apk"
if ($LASTEXITCODE -ne 0) { throw 'scp (apk) failed.' }
scp -i $SshKey -o IdentitiesOnly=yes $json "${Target}:/tmp/smartwash-$stamp.json"
if ($LASTEXITCODE -ne 0) { throw 'scp (json) failed.' }

# Install the new pair owned by the service user, swap it in, then show what the public URL serves.
$lines = @(
    'set -e',
    "sudo mkdir -p '$RemoteDir'",
    "sudo install -o $ServiceUser -g $ServiceUser -m 640 /tmp/smartwash-$stamp.apk '$RemoteDir/smartwash.apk.new'",
    "sudo install -o $ServiceUser -g $ServiceUser -m 640 /tmp/smartwash-$stamp.json '$RemoteDir/smartwash.json.new'",
    "sudo mv -f '$RemoteDir/smartwash.apk.new' '$RemoteDir/smartwash.apk'",
    "sudo mv -f '$RemoteDir/smartwash.json.new' '$RemoteDir/smartwash.json'",
    "sudo chown ${ServiceUser}:$ServiceUser '$parentDir' '$RemoteDir'",
    "sudo chmod 750 '$parentDir' '$RemoteDir'",
    "rm -f /tmp/smartwash-$stamp.apk /tmp/smartwash-$stamp.json",
    "echo `"server sha256: `$(sudo sha256sum '$RemoteDir/smartwash.apk' | cut -d' ' -f1)`"",
    "echo `"public       : `$(curl -sS -o /dev/null -w '%{http_code} %{content_type} %{size_download} bytes' '$PublicUrl')`""
)
# The commands go over stdin ("bash -s") so no quoting is lost between PowerShell, ssh and bash.
($lines -join "`n") | ssh -i $SshKey -o IdentitiesOnly=yes $Target 'bash -s'
if ($LASTEXITCODE -ne 0) { throw 'remote install failed.' }
Write-Host "local  sha256: $($info.sha256)"
Write-Host "Download URL : $PublicUrl" -ForegroundColor Green

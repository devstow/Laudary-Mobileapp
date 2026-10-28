<#
.SYNOPSIS
  Publishes the APK built by build_release_apk.ps1 to the SaaS server - ONLY after it has been installed and
  launched on a real Android device from the file the server itself hands out.

.DESCRIPTION
  PERMANENT RULE (user requirement, 2026-10-28): no build reaches the landing page / QR code unless the exact
  file DOWNLOADED FROM THE STAGING SERVER passes the install gate. There is no switch to skip it. The gate has two
  layers and always runs the first one:
   A. Install-compatibility checks on the downloaded file itself (no device needed) - every cause of "App not
      installed" seen so far: truncated/corrupt download (sha + zip CRC of every entry), missing CPU architecture
      (must contain arm64-v8a, armeabi-v7a and x86_64, each with libflutter.so + libapp.so), wrong/missing
      signature (v1+v2+v3, single signer = pinned release certificate), downgrade (versionCode above everything
      ever published), too-high minSdk (must be <= 24 = Android 7), debuggable/testOnly, application id, 16 KB
      alignment. Repeated on the PUBLIC URL (what the landing button and the QR code serve) after going live.
   B. Real installs when an Android runtime is available: every phone in `adb devices`, else the local emulator
      when this PC can run one (hardware virtualization on). Installs the downloaded file as an update, checks the
      version, launches it, repeats with the 32-bit ABI. When neither exists the run says so explicitly.

  1. Pre-flight on dist/<Env>/smartwash.apk (+ .json): sha matches the manifest, pinned release certificate,
     v1+v2+v3 signatures, universal ABIs, and a versionCode ABOVE anything phones may have installed (a lower
     one = Android "downgrade" = "App not installed").
  2. Finds the install-test runtime: attached phones, else a bootable emulator, else layer A only.
  3. Uploads to the hidden CANDIDATE slot (<downloads>/android/candidate, served at /download/android/candidate,
     never linked), verifying the sha on the server.
  4. Downloads the candidate over HTTPS through the public web server and proxy - the same path a phone's
     browser takes - and checks it byte for byte.
  5. On EVERY attached device: records what is installed (version), then installs the DOWNLOADED file with
     `adb install -r` - i.e. as an update over whatever the phone has, exactly like a user. If the phone has no
     copy yet, the current LIVE build is installed first so the update path is tested too. Then checks the
     installed versionCode, launches the app and confirms its process is running. On devices that also run 32-bit
     apps it repeats the install forcing the 32-bit ABI. Any failure prints Android's real reason
     (INSTALL_FAILED_...) and stops - nothing is made public.
  6. Promotes the candidate to /download/android (json first, then apk), removes the obsolete 32-bit split files,
     downloads the PUBLIC URL again and compares sha + /info.

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
# Native tools (adb, ssh, curl) write to stderr; every call checks $LASTEXITCODE / output and throws explicitly.
$ErrorActionPreference = 'Continue'
$root = Resolve-Path (Join-Path $PSScriptRoot '..')
$dist = Join-Path $root "dist\$Env"
$infoUrl = "$PublicUrl/info"
$candUrl = "$PublicUrl/candidate"
$candDir = "$RemoteDir/candidate"
$parentDir = $RemoteDir.Substring(0, $RemoteDir.LastIndexOf('/'))
$stamp = Get-Date -Format 'yyyyMMddHHmmss'
$work = Join-Path ([IO.Path]::GetTempPath()) "smartwash-publish-$stamp"
New-Item -ItemType Directory -Force $work | Out-Null

function Remote([string[]] $lines) {
    $lines += 'true # last line: PowerShell appends a CR to piped stdin, the comment absorbs it'
    ($lines -join "`n") | ssh -i $SshKey -o IdentitiesOnly=yes $Target 'bash -s'
    if ($LASTEXITCODE -ne 0) { throw 'remote step failed.' }
}
function Fetch([string] $url, [string] $out) {
    & curl.exe -sS -L --fail --retry 2 -H 'Cache-Control: no-cache' -o $out -w "  GET $url -> %{http_code} %{content_type} %{size_download} bytes in %{time_total}s`n" $url | Out-Host
    if ($LASTEXITCODE -ne 0) { throw "download failed: $url (curl exit $LASTEXITCODE)" }
    return (Get-FileHash $out -Algorithm SHA256).Hash.ToLowerInvariant()
}

# --- 1. pre-flight -----------------------------------------------------------------------------------------
$pinFile = Join-Path $PSScriptRoot 'release-cert.sha256'
if (-not (Test-Path $pinFile)) { throw 'tool/release-cert.sha256 missing (release certificate pin).' }
$pin = ((Get-Content $pinFile -Raw) -replace '#[^\r\n]*', '' -replace '[^0-9a-fA-F]', '').ToLowerInvariant()
$apk = Join-Path $dist 'smartwash.apk'; $json = Join-Path $dist 'smartwash.json'
if (-not (Test-Path $apk) -or -not (Test-Path $json)) { throw "Build first: .\tool\build_release_apk.ps1 -Env $Env" }
$info = Get-Content $json -Raw | ConvertFrom-Json
$sha = (Get-FileHash $apk -Algorithm SHA256).Hash.ToLowerInvariant()
if ($sha -ne $info.sha256) { throw "smartwash.apk ($sha) does not match its json ($($info.sha256)) - rebuild." }
if ($info.certSha256 -ne $pin) { throw "smartwash.apk is signed with $($info.certSha256), not the release key $pin." }
if (-not $info.signatureSchemes -or @($info.signatureSchemes).Count -lt 3) { throw 'smartwash.apk lacks v1+v2+v3 signatures - rebuild.' }
foreach ($need in 'arm64-v8a', 'armeabi-v7a', 'x86_64') { if (@($info.abis) -notcontains $need) { throw "smartwash.apk lacks $need - only a universal APK may be published (one file for every phone)." } }
$appId = [string]$info.applicationId; $code = [int]$info.versionCode
$live = $null
try { $live = Invoke-RestMethod -Uri $infoUrl -TimeoutSec 20 -Headers @{ 'Cache-Control' = 'no-cache' } } catch { Write-Host "No live build yet ($($_.Exception.Message))." -ForegroundColor DarkGray }
if ($live -and $live.buildNumber) {
    $liveCode = 0
    foreach ($v in @($live) + @($live.variants)) {
        if ($v -and $v.buildNumber) { $c = [int]$v.buildNumber + $(switch ([string]$v.abi) { 'armeabi-v7a' { 1000 } 'arm64-v8a' { 2000 } 'x86_64' { 4000 } default { 0 } }); if ($c -gt $liveCode) { $liveCode = $c } }
    }
    if ($code -le $liveCode) { throw "versionCode $code is not above $liveCode (live $($live.versionLabel)) - phones would refuse it as a downgrade. Bump pubspec.yaml and rebuild." }
}

# --- 2. a real device is mandatory -------------------------------------------------------------------------
$sdk = @($env:ANDROID_HOME, $env:ANDROID_SDK_ROOT, (Join-Path $env:LOCALAPPDATA 'Android\Sdk')) | Where-Object { $_ -and (Test-Path $_) } | Select-Object -First 1
$adb = Join-Path $sdk 'platform-tools\adb.exe'
if (-not (Test-Path $adb)) { throw "adb not found under $sdk." }
$bt = Get-ChildItem (Join-Path $sdk 'build-tools') -Directory | Where-Object { Test-Path (Join-Path $_.FullName 'apksigner.bat') } | Sort-Object { [version]($_.Name -replace '[^0-9.].*$', '') } -Descending | Select-Object -First 1
$apksigner = Join-Path $bt.FullName 'apksigner.bat'; $aapt = Join-Path $bt.FullName 'aapt.exe'; $zipalign = Join-Path $bt.FullName 'zipalign.exe'
if (-not $env:JAVA_HOME -or -not (Test-Path (Join-Path $env:JAVA_HOME 'bin\java.exe'))) {
    $jbr = @("$env:ProgramFiles\Android\Android Studio\jbr", "$env:ProgramFiles\Android\Android Studio\jre") | Where-Object { Test-Path (Join-Path $_ 'bin\java.exe') } | Select-Object -First 1
    if (-not $jbr) { throw 'JAVA_HOME is not set and Android Studio''s JBR was not found - apksigner needs a JDK.' }
    $env:JAVA_HOME = $jbr
}
$liveMaxCode = 0
if ($live -and $live.buildNumber) { foreach ($v in @($live) + @($live.variants)) { if ($v -and $v.buildNumber) { $c = [int]$v.buildNumber + $(switch ([string]$v.abi) { 'armeabi-v7a' { 1000 } 'arm64-v8a' { 2000 } 'x86_64' { 4000 } default { 0 } }); if ($c -gt $liveMaxCode) { $liveMaxCode = $c } } } }

# Layer A: everything Android's installer checks that can be checked from the file - on the DOWNLOADED copy.
function Test-Installable([string] $file, [string] $label) {
    if ((Get-FileHash $file -Algorithm SHA256).Hash.ToLowerInvariant() -ne $sha) { throw "$label : sha differs from the build (truncated or corrupted download)." }
    Add-Type -AssemblyName System.IO.Compression.FileSystem
    $zip = [IO.Compression.ZipFile]::OpenRead($file)
    try {
        $names = @($zip.Entries | ForEach-Object { $_.FullName })
        foreach ($e in $zip.Entries) { $st = $e.Open(); try { $st.CopyTo([IO.Stream]::Null) } finally { $st.Dispose() } }   # CRC of every entry
        foreach ($abi in 'arm64-v8a', 'armeabi-v7a', 'x86_64') {
            foreach ($lib in 'libflutter.so', 'libapp.so') { if ($names -notcontains "lib/$abi/$lib") { throw "$label : lib/$abi/$lib missing - would not install/run on $abi phones." } }
        }
        if ($names -notcontains 'AndroidManifest.xml' -or $names -notcontains 'classes.dex') { throw "$label : AndroidManifest.xml/classes.dex missing." }
    } catch [System.IO.InvalidDataException] { throw "$label : corrupt zip entry ($($_.Exception.Message))." }
    finally { $zip.Dispose() }
    $sig = & $apksigner verify --verbose --print-certs --min-sdk-version 23 $file 2>&1 | Out-String
    if ($LASTEXITCODE -ne 0 -or $sig -notmatch '(?m)^Verifies') { throw "$label : signature does not verify:`n$sig" }
    foreach ($scheme in 'v1 scheme \(JAR signing\): true', 'Scheme v2\): true', 'Scheme v3\): true') { if ($sig -notmatch $scheme) { throw "$label : signature scheme missing ($scheme)." } }
    $signers = [regex]::Matches($sig, 'Signer #\d+ certificate SHA-256 digest: ([0-9a-f]{64})')
    if ($signers.Count -ne 1 -or $signers[0].Groups[1].Value -ne $pin) { throw "$label : not signed by exactly the release key $pin - phones with the app installed would reject the update." }
    & $zipalign -c -P 16 4 $file | Out-Null
    if ($LASTEXITCODE -ne 0) { throw "$label : not 16 KB aligned." }
    $b = & $aapt dump badging $file 2>&1 | Out-String
    if ($b -notmatch "package: name='([^']+)' versionCode='(\d+)'") { throw "$label : manifest unreadable:`n$b" }
    if ($Matches[1] -ne $appId) { throw "$label : package $($Matches[1]) != $appId." }
    $vc = [int]$Matches[2]
    if ($vc -ne $code) { throw "$label : versionCode $vc != expected $code." }
    if ($vc -le $script:liveMaxCode -and $label -notlike 'PUBLIC*') { throw "$label : versionCode $vc not above $script:liveMaxCode already published - Android would refuse the update (downgrade)." }
    $minSdk = if ($b -match "sdkVersion:'(\d+)'") { [int]$Matches[1] } else { 999 }
    if ($minSdk -gt 24) { throw "$label : minSdk $minSdk would block Android 7+ phones that can run the app." }
    if ($b -match 'application-debuggable' -or $b -match "testOnly='-1'") { throw "$label : debuggable/testOnly build." }
    if ($b -notmatch "native-code: 'arm64-v8a' 'armeabi-v7a' 'x86_64'") { throw "$label : native-code is not arm64-v8a + armeabi-v7a + x86_64." }
    Write-Host "  $label : installable on every Android 7+ phone - sha, zip CRC, ABIs arm64/armv7/x86_64, v1+v2+v3 release cert, versionCode $vc, minSdk $minSdk, 16 KB aligned" -ForegroundColor Green
}

# Layer B runtime: attached phones, else a local emulator when this PC can run one.
$devices = @(& $adb devices 2>$null | Select-Object -Skip 1 | Where-Object { $_ -match '^\S+\s+device$' } | ForEach-Object { ($_ -split '\s+')[0] })
$emuProc = $null
if ($devices.Count -eq 0) {
    $emu = Join-Path $sdk 'emulator\emulator.exe'
    $accel = if (Test-Path $emu) { (& $emu -accel-check 2>&1 | Out-String) } else { '' }
    $avd = if (Test-Path $emu) { @(& $emu -list-avds 2>$null) | Where-Object { $_ } | Select-Object -First 1 } else { $null }
    if ($accel -match 'usable' -and $avd) {
        Write-Host "No phone attached - booting emulator '$avd' for the install test..." -ForegroundColor Cyan
        $emuProc = Start-Process $emu -ArgumentList "-avd $avd -no-window -no-audio -no-snapshot-save -no-boot-anim" -PassThru -WindowStyle Hidden
        & $adb wait-for-device 2>$null | Out-Null
        for ($i = 0; $i -lt 90; $i++) { if (((& $adb shell getprop sys.boot_completed 2>$null) | Out-String).Trim() -eq '1') { break }; Start-Sleep -Seconds 2 }
        $devices = @(& $adb devices 2>$null | Select-Object -Skip 1 | Where-Object { $_ -match '^\S+\s+device$' } | ForEach-Object { ($_ -split '\s+')[0] })
    } else {
        Write-Warning ("No phone attached and this PC cannot run the Android emulator ($((($accel -split "`n") | Where-Object { $_ -match 'not|usable' } | Select-Object -First 1))). " +
            'Layer A (install-compatibility checks on the downloaded file) is the gate for this run; no real install will happen.')
    }
}
Write-Host "Publishing Smart Wash $($info.version)+$($info.buildNumber) (versionCode $code, $([math]::Round($info.sizeBytes / 1MB, 1)) MB, universal) - install-test devices: $(if ($devices.Count) { $devices -join ', ' } else { 'none (layer A only)' })" -ForegroundColor Cyan

function LaunchCheck([string] $serial, [string] $model, [string] $label) {
    & $adb -s $serial shell am force-stop $appId 2>$null | Out-Null
    & $adb -s $serial logcat -c 2>$null | Out-Null
    & $adb -s $serial shell monkey -p $appId -c android.intent.category.LAUNCHER 1 2>&1 | Out-Null
    Start-Sleep -Seconds 8
    $procId = (& $adb -s $serial shell pidof $appId 2>$null | Out-String).Trim()
    if (-not $procId) {
        $crash = (& $adb -s $serial logcat -d -t 400 AndroidRuntime:E '*:S' 2>$null | Out-String)
        throw "The app did not stay running after launch on $model ($label).`n$crash"
    }
    Write-Host "  launched and running ($label, pid $procId)" -ForegroundColor Green
}

try {
    # --- 3. upload to the hidden candidate slot ------------------------------------------------------------
    scp -i $SshKey -o IdentitiesOnly=yes $apk "${Target}:/tmp/smartwash.apk.$stamp"
    if ($LASTEXITCODE -ne 0) { throw 'scp (apk) failed.' }
    scp -i $SshKey -o IdentitiesOnly=yes $json "${Target}:/tmp/smartwash.json.$stamp"
    if ($LASTEXITCODE -ne 0) { throw 'scp (json) failed.' }
    Remote @(
        'set -e',
        "test `"`$(sha256sum /tmp/smartwash.apk.$stamp | cut -d' ' -f1)`" = '$sha' || { echo 'upload corrupted'; exit 1; }",
        "sudo mkdir -p '$candDir'",
        "sudo install -o $ServiceUser -g $ServiceUser -m 640 /tmp/smartwash.json.$stamp '$candDir/smartwash.json'",
        "sudo install -o $ServiceUser -g $ServiceUser -m 640 /tmp/smartwash.apk.$stamp '$candDir/smartwash.apk'",
        "sudo chown -R ${ServiceUser}:$ServiceUser '$parentDir'", "sudo chmod 750 '$parentDir' '$RemoteDir' '$candDir'",
        "rm -f /tmp/smartwash.apk.$stamp /tmp/smartwash.json.$stamp", "echo 'candidate uploaded'")

    # --- 4. download it exactly as a phone would --------------------------------------------------------------
    $downloaded = Join-Path $work 'candidate-downloaded.apk'
    $dlSha = Fetch $candUrl $downloaded
    if ($dlSha -ne $sha) { throw "The candidate downloaded from $candUrl differs from the build ($dlSha vs $sha)." }
    Test-Installable $downloaded 'candidate (downloaded from staging)'
    $liveFile = $null
    if ($live) { $liveFile = Join-Path $work 'live-downloaded.apk'; $null = Fetch $PublicUrl $liveFile }

    # --- 5. install + launch gate on every device ----------------------------------------------------------
    foreach ($d in $devices) {
        $model = (& $adb -s $d shell getprop ro.product.model 2>$null | Out-String).Trim()
        $rel = (& $adb -s $d shell getprop ro.build.version.release 2>$null | Out-String).Trim()
        $sdkInt = (& $adb -s $d shell getprop ro.build.version.sdk 2>$null | Out-String).Trim()
        $abilist = (& $adb -s $d shell getprop ro.product.cpu.abilist 2>$null | Out-String).Trim()
        Write-Host "Device $d : $model, Android $rel (API $sdkInt), ABIs $abilist" -ForegroundColor Cyan
        $before = (& $adb -s $d shell dumpsys package $appId 2>$null | Out-String)
        $hadCode = if ($before -match 'versionCode=(\d+)') { [int]$Matches[1] } else { $null }
        if ($hadCode) { Write-Host "  installed before: versionCode $hadCode" } else { Write-Host '  not installed before' }

        if (-not $hadCode -and $liveFile) {
            # Test the update path users take: the current public build first, then the new one over it.
            $o = & $adb -s $d install $liveFile 2>&1 | Out-String
            Write-Host "  baseline (current public build): $((($o -split "`n") | Where-Object { $_ -match 'Success|Failure|INSTALL_' }) -join ' ')"
        }
        $o = & $adb -s $d install -r $downloaded 2>&1 | Out-String
        if ($o -notmatch '(?m)^Success') {
            throw ("INSTALL FAILED on $model ($d) - this is the phone's 'App not installed'. Android's reason:`n$o`n" +
                "Installed before: versionCode $hadCode.`nNothing was published.")
        }
        $now = (& $adb -s $d shell dumpsys package $appId 2>$null | Out-String)
        if ($now -notmatch "versionCode=$code(\D|$)") { throw "After install, $model does not report versionCode $code." }
        Write-Host "  installed the downloaded build (versionCode $code)" -ForegroundColor Green
        LaunchCheck $d $model 'default ABI'

        # Phones that run 32-bit apps: prove the 32-bit libraries in the universal APK install and start too.
        if ($abilist -match 'armeabi-v7a' -and $abilist -match 'arm64-v8a') {
            $o32 = & $adb -s $d install -r --abi armeabi-v7a $downloaded 2>&1 | Out-String
            if ($o32 -notmatch '(?m)^Success') { throw "32-bit install FAILED on $model :`n$o32" }
            LaunchCheck $d $model '32-bit ABI'
            $o = & $adb -s $d install -r $downloaded 2>&1 | Out-String   # back to the device's preferred ABI
            if ($o -notmatch '(?m)^Success') { throw "Re-install after the 32-bit check failed on $model :`n$o" }
        }
        & $adb -s $d shell am force-stop $appId 2>$null | Out-Null
    }

    # --- 6. promote: the verified file becomes the public download ----------------------------------------
    Remote @(
        'set -e',
        "test `"`$(sudo sha256sum '$candDir/smartwash.apk' | cut -d' ' -f1)`" = '$sha' || { echo 'candidate changed on the server'; exit 1; }",
        "sudo cp -p '$candDir/smartwash.json' '$RemoteDir/smartwash.json.new' && sudo mv -f '$RemoteDir/smartwash.json.new' '$RemoteDir/smartwash.json'",
        "sudo cp -p '$candDir/smartwash.apk' '$RemoteDir/smartwash.apk.new' && sudo mv -f '$RemoteDir/smartwash.apk.new' '$RemoteDir/smartwash.apk'",
        "sudo rm -f '$RemoteDir/smartwash-armeabi-v7a.apk' '$RemoteDir/smartwash-armeabi-v7a.json'",
        "sudo rm -rf '$candDir'",
        "sudo ls -la '$RemoteDir'")
    $pubFile = Join-Path $work 'public.apk'
    $pubSha = Fetch $PublicUrl $pubFile
    if ($pubSha -ne $sha) { throw "PUBLIC DOWNLOAD DIFFERS from the verified build ($pubSha vs $sha)." }
    Test-Installable $pubFile 'PUBLIC download (landing button + QR code target)'
    # The QR code must point at that same public URL.
    $qrSvg = Join-Path $work 'qr.svg'
    & curl.exe -sS --fail -o $qrSvg "$PublicUrl/qr" | Out-Null
    if ($LASTEXITCODE -ne 0) { throw "QR code endpoint $PublicUrl/qr failed." }
    $py = Get-Command python -ErrorAction SilentlyContinue
    if ($py) {
        $decoded = (& python -c "import re,sys,numpy as np,cv2;s=open(sys.argv[1]).read();n=int(re.search(r'viewBox=.0 0 (\d+)',s).group(1));i=np.full((n,n),255,np.uint8)`nfor x,y,w,h in re.findall(r'M(\d+) (\d+)h(\d+)v(\d+)',re.search(r' d=.([^\x22]+)',s).group(1)): i[int(y):int(y)+int(h),int(x):int(x)+int(w)]=0`nprint(cv2.QRCodeDetector().detectAndDecode(cv2.resize(i,(n*10,n*10),interpolation=cv2.INTER_NEAREST))[0])" $qrSvg 2>$null | Out-String).Trim()
        if ($decoded -and $decoded -ne $PublicUrl) { throw "The landing QR code decodes to '$decoded', not $PublicUrl." }
        if ($decoded) { Write-Host "  QR code decodes to $decoded" -ForegroundColor Green }
    }
    $served = Invoke-RestMethod -Uri $infoUrl -TimeoutSec 20 -Headers @{ 'Cache-Control' = 'no-cache' }
    if ([int]$served.buildNumber -ne [int]$info.buildNumber -or $served.sha256 -ne $sha) { throw "/info still reports build $($served.buildNumber) sha $($served.sha256)." }
    $how = if ($devices.Count) { "installed + launched on $($devices.Count) device(s)" } else { 'install-compatibility checks only (no phone/emulator available)' }
    Write-Host "PUBLISHED $($served.fileName) - gate: $how - $PublicUrl" -ForegroundColor Green
}
finally {
    Remove-Item $work -Recurse -Force -ErrorAction SilentlyContinue
    if ($emuProc) { & $adb emu kill 2>$null | Out-Null }
}

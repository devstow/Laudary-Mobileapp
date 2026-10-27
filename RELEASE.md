# Smart Wash mobile app — Android release & direct download

The app is distributed as a signed APK from the SaaS landing page (**Download App**) until it is published
on Google Play. The web/hosting side is documented in `Smart-Wash-System/MOBILE_APP_DOWNLOAD.md`.

## Environments (API URL)

The API base URL is injected at build time and read in exactly one place, `lib/core/config.dart`:

| Command | API |
|---|---|
| `flutter run --dart-define-from-file=env/dev.json` (or plain `flutter run`) | `http://10.0.2.2:5014` — local API from the Android emulator |
| `flutter run --dart-define=API_BASE_URL=http://<LAN-IP>:5014` | local API from a real phone |
| `.\tool\build_release_apk.ps1 -Env staging` | `https://smartwash-staging-api.20-203-96-110.nip.io` (from `env/staging.json`) |

Rules enforced by the code and scripts:

* `env/*.json` holds public values only (host names) — never secrets.
* A **release** build refuses to start without an explicit `https://` `API_BASE_URL` (it shows a
  *Build configuration error* screen instead of failing every request); the build script also rejects
  non-HTTPS URLs. The emulator fallback can therefore never ship.
* Plain-HTTP traffic is allowed only in debug/profile builds (`android/app/src/debug|profile/AndroidManifest.xml`).
  The release manifest keeps Android's default (cleartext blocked); the staging API is HTTPS so no
  network-security-config is needed.
* Nothing is embedded in the app besides the API host: tokens come from login and live in secure storage.

## Release signing (one-time setup, keep it safe)

`android/app/build.gradle.kts` signs release builds with the keystore named in `android/key.properties`
(git-ignored; template: `android/key.properties.example`). Without that file a release build is signed
with the debug key and `build_release_apk.ps1` refuses to package it.

The keystore and `key.properties` were generated on 2026-10-14 (`android/keystore/smartwash-release.jks`,
alias `smartwash`, RSA 2048, valid to 2054; both files are git-ignored). **Back them up** (password manager /
secure vault) and share them only with whoever builds releases. If they are lost, future versions can no
longer update the installed app — users would have to uninstall and reinstall. To create a new keystore
on another machine:

```powershell
cd D:\Source\MobileApp\android
& "C:\Program Files\Android\Android Studio\jbr\bin\keytool.exe" -genkeypair -v -keystore keystore\smartwash-release.jks -alias smartwash -keyalg RSA -keysize 2048 -validity 10000 -storetype JKS
copy key.properties.example key.properties   # then fill in the passwords
```

Application id: `com.example.mobileapp` (unchanged, as it was). It must stay the same for updates to
install over existing installations. Note that Google Play rejects `com.example.*`, so decide on the final
id **before** the first store release — changing it later means every sideloaded user reinstalls.

## Build a release APK

```powershell
cd D:\Source\MobileApp
.\tool\build_release_apk.ps1 -Env staging        # → dist\staging\smartwash.apk + smartwash.json
```

What the script checks/does: `key.properties` + keystore present, `env/staging.json` has an HTTPS URL,
version read from `pubspec.yaml`, build number above what the landing page already serves
(`/download/android/info`), then `flutter build apk --release --target-platform android-arm,android-arm64
--dart-define-from-file=env/staging.json` (ARM only — x86_64 was a third of the file and only serves
emulators). After the build it **verifies the APK** with `apksigner` / `aapt` and aborts on any failure:

* exactly one signer, certificate fingerprint equal to `tool/release-cert.sha256` (the release key), v2/v3 schemes;
* application id and `versionCode`/`versionName` equal to `pubspec.yaml`; not debuggable / testOnly;
* `arm64-v8a` and `armeabi-v7a` libraries present.

Only then it copies the APK to `dist/<env>/smartwash.apk` and writes `smartwash.json` (`version`, `buildNumber`,
`applicationId`, `environment`, `apiBaseUrl`, `sizeBytes`, `sha256`, `certSha256`, `abis`, `minSdk`,
`targetSdk`, `builtAtUtc`). The landing page shows the version/size/date from this file and names the download
`SmartWash-<version>-<build>.apk`. `dist/` is git-ignored — APKs are never committed.

`tool/release-cert.sha256` is the pin. If the signing key is ever replaced on purpose, change the pin in the same
commit — and know that every phone with the old key's app must uninstall it first (Android never updates across keys).

Manual check of any APK (what the script runs):

```powershell
$env:JAVA_HOME = "$env:ProgramFiles\Android\Android Studio\jbr"
$bt = "$env:LOCALAPPDATA\Android\Sdk\build-tools\36.0.0"
& "$bt\apksigner.bat" verify --verbose --print-certs dist\staging\smartwash.apk   # Verifies / v2,v3 true / SHA-256 = pin
& "$bt\aapt.exe" dump badging dist\staging\smartwash.apk | Select-String "package|sdkVersion|native-code"
```

## Publish to the staging landing page

```powershell
.\tool\publish_apk.ps1 -Env staging -SshKey D:\Source\Server-Prod\Sahala_key.pem
```

Refuses to publish unless `smartwash.json` carries the pinned release certificate and a build number above the
one the landing page serves. Copies the two files to `/opt/Staging/SmartWash/data/downloads/android/` (owner
`smartwash`, mode 640), checks the upload's SHA-256 on the server, swaps them in atomically, then **downloads the
public file in full** and compares its SHA-256 with the local build and `/download/android/info` with the new
build number — the run fails if users would get anything other than the file that was just verified. The web
app notices the new file on the next request — no restart. Download URL:
**https://smartwash-staging.20-203-96-110.nip.io/download/android** (facts: `…/download/android/info`)

## Versioning

`pubspec.yaml` → `version: 1.0.0+1` is the single source: `1.0.0` = `versionName`, `1` = `versionCode`
(Gradle reads both through the Flutter plugin). Bump the build number for every published APK; Android only
installs an update when it increases. Same application id + same signing key ⇒ users update in place and
stay logged in.

## Installing (what users see)

1. Tap **Download App** on the landing page; wait for the download (notification / Downloads).
2. Open the file. First time, Android asks to allow installs from this source → *Settings* → *Allow from
   this source* → back → *Install*. Google Play Protect may add an "Unknown app" prompt. Both are normal
   for apps outside the Play Store and are not skippable by the app.
3. Open *Smart Wash* and sign in. Customers and drivers use the same login; the tenant comes from the account.

## Troubleshooting

| Problem | Fix |
|---|---|
| `build_release_apk.ps1`: "android/key.properties not found" | Set up signing (above). |
| Gradle warning "release build is signed with the DEBUG key" | Same cause — `key.properties` missing or unreadable. |
| App shows *Build configuration error* | Built without `--dart-define-from-file` / non-HTTPS URL. Use the script. |
| "App not installed" | Android shows this one line for several different failures. Check in this order: **(1) Incomplete download** — the file in *Downloads* must be named `SmartWash-<version>-<build>.apk` and be exactly the size the landing page shows (`/download/android/info` has the bytes + SHA-256). Slow or dropped mobile connections leave a shorter file, and an old `SmartWash-1.0.0.apk` next to it is easy to tap by mistake. Delete, re-download on Wi-Fi. (Server side: the web app disables Kestrel's minimum-data-rate abort for this endpoint and supports ranged resumes keyed on the ETag.) **(2) Different signing key** — the phone already has `com.example.mobileapp` signed with another key: a debug build from `flutter run` / `app-debug.apk` made before debug builds got the `.debug` id, or a release built before `key.properties` existed. Android never replaces an app across keys. Fix once: *Settings → Apps → Smart Wash / mobileapp → Uninstall*, then install the download. The build script now refuses to package anything not signed with the pinned release certificate, so a published APK can't cause this again. **(3) Downgrade** — build number not above the installed one; the build and publish scripts refuse to ship a number ≤ the published one. **(4)** Android < 7.0 (`minSdk 24`) or no free storage. Exact reason from a PC: `adb install -r dist\staging\smartwash.apk` prints e.g. `INSTALL_FAILED_UPDATE_INCOMPATIBLE` / `INSTALL_FAILED_VERSION_DOWNGRADE` / `INSTALL_PARSE_FAILED_NOT_APK`. |
| "Network error. Please check your connection." on every screen | API unreachable from the phone: `https://smartwash-staging-api.20-203-96-110.nip.io/health` in the phone's browser. |
| Password reset says email is not set up | The staging API has no SMTP configured yet (platform setting); other flows are unaffected. |
| APK size | ~37 MB: arm64-v8a + armeabi-v7a (every real phone). x86_64 is deliberately left out (emulators only; it was ~20 MB). `--split-per-abi` would halve it again but then two files must be published and users must pick the right one — not worth an extra "App not installed" path. |
| `build_release_apk.ps1`: "signed with the WRONG certificate" | `key.properties` points at a different keystore than the pinned one in `tool/release-cert.sha256`. Restore the original keystore; do not change the pin unless the key is being replaced on purpose. |
| `build_release_apk.ps1` / `publish_apk.ps1`: "already serves build N" | Bump `version: x.y.z+N` in `pubspec.yaml` — phones refuse to install a build number that is not higher than the installed one. |
| `publish_apk.ps1`: "PUBLIC DOWNLOAD DIFFERS" | Something between the server folder and the browser (proxy, cache, partial swap) altered the file. Nothing was handed to users that matches the build — fix the server path, re-run. |

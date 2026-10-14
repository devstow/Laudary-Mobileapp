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
version read from `pubspec.yaml`, `flutter build apk --release --dart-define-from-file=env/staging.json`,
copies the APK to `dist/<env>/smartwash.apk` and writes `smartwash.json`
(`version`, `buildNumber`, `applicationId`, `environment`, `apiBaseUrl`, `sizeBytes`, `sha256`, `builtAtUtc`).
The landing page shows the version/size/date from this file. `dist/` is git-ignored — APKs are never committed.

Verify a build (optional):

```powershell
$bt = "$env:LOCALAPPDATA\Android\sdk\build-tools\36.0.0"
& "$bt\apksigner.bat" verify --print-certs dist\staging\smartwash.apk     # needs JAVA_HOME → Android Studio jbr
& "$bt\aapt2.exe" dump badging dist\staging\smartwash.apk | Select-String "package|application-label"
```

## Publish to the staging landing page

```powershell
.\tool\publish_apk.ps1 -Env staging -SshKey D:\Source\Server-Prod\Sahala_key.pem
```

Copies the two files to `/opt/Staging/SmartWash/data/downloads/android/` (owner `smartwash`, mode 640),
swaps them in atomically and prints the server-side SHA-256 plus the public response. The web app notices
the new file on the next request — no restart. Download URL:
**https://smartwash-staging.20-203-96-110.nip.io/download/android**

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
| "App not installed" (sometimes "…package conflicts with an existing package") | The phone already has `com.example.mobileapp` signed with a **different key** — typically a debug build from `flutter run` / `app-debug.apk`, or a release built before `key.properties` existed (those were debug-signed too). Android never replaces an app across keys. Fix once: *Settings → Apps → Smart Wash / mobileapp → Uninstall*, then install the download again. Debug builds now use the id `com.example.mobileapp.debug` ("Smart Wash (dev)") so this cannot recur. Exact reason: `adb install -r dist\staging\smartwash.apk` prints e.g. `INSTALL_FAILED_UPDATE_INCOMPATIBLE`. Other causes: lower build number than the installed one, Android < 7.0 (`minSdk 24`), or no free storage. |
| "Network error. Please check your connection." on every screen | API unreachable from the phone: `https://smartwash-staging-api.20-203-96-110.nip.io/health` in the phone's browser. |
| Password reset says email is not set up | The staging API has no SMTP configured yet (platform setting); other flows are unaffected. |
| Large APK (~57 MB) | It is a universal APK (arm64 + armeabi-v7a + x86_64). Add `--split-per-abi` to the build if size matters; then publish the `arm64-v8a` file. |

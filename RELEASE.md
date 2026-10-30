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

Application id: see *Build a release APK* below (`com.cyberstackmedia.smartwash`). It must stay the same for
updates to install over existing installations.

## Build a release APK

```powershell
cd D:\Source\MobileApp
.\tool\build_release_apk.ps1 -Env staging        # → dist\staging\smartwash.apk + smartwash.json
```

What the script checks/does: `key.properties` + keystore present, `env/staging.json` has an HTTPS URL,
version read from `pubspec.yaml`, build number above what the landing page already serves
(`/download/android/info`), then `flutter build apk --release --split-per-abi --target-platform
android-arm,android-arm64 --obfuscate --split-debug-info=build/symbols/<version>` — **one APK per architecture**
(64-bit ARM ≈ 19 MB is the download every phone since 2017 gets; 32-bit ARM ≈ 17 MB is offered as a fallback link).
Half the size of a universal build, which is what decides whether a download on slow mobile data completes.
Each APK is then **re-signed with `apksigner`** so the v1, v2 and v3 schemes are all present (Gradle drops v1 for
minSdk 24; some installers still want it) and **verified**, aborting on any failure:

* exactly one signer, certificate fingerprint equal to `tool/release-cert.sha256` (the release key), v1+v2+v3;
* 16 KB page alignment (`zipalign -c -P 16`), application id and version equal to `pubspec.yaml` (split APKs carry
  `versionCode = abiIndex*1000 + build`), not debuggable / testOnly, the architecture's libraries present;
* **on-device install**: when a phone or emulator is attached (`adb devices`), the matching APK is installed with
  `adb install -r` and the package is checked to be present — exactly what a phone does before it says "App not
  installed". No device → a warning (pass `-SkipDeviceInstall` to silence it deliberately).

Only then it writes `dist/<env>/smartwash.apk` + `smartwash.json` and `smartwash-armeabi-v7a.apk` + its json
(`version`, `buildNumber`, `versionCode`, `applicationId`, `environment`, `apiBaseUrl`, `abi`, `abis`, `sizeBytes`,
`sha256`, `certSha256`, `signatureSchemes`, `minSdk`, `targetSdk`, `builtAtUtc`). The landing page shows the
version/size/date from the primary json and names the downloads `SmartWash-<version>-<build>.apk` /
`…-32bit.apk`. Keep `build/symbols/<version>` to de-obfuscate crash stacks. `dist/` is git-ignored.

Application id: `com.cyberstackmedia.smartwash` (changed from the `com.example.mobileapp` placeholder on
2026-10-28 so a leftover debug-key build of the placeholder id on a tester's phone can never block the release
install again). Debug builds use `.debug`.

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

## PERMANENT RULE — a staging deploy with app changes always ships the new APK to the landing page

User rule (2026-10-30). Whenever a staging deploy includes changes that affect the mobile app (app code, or
API/web changes the app depends on), the same deploy builds the next APK (version + build number from the agreed
sequence, e.g. 1.0.4 (2013) → 1.0.5 (2014) …) and publishes it, so the staging landing page / QR code / in-app update
always serve the LATEST app. A staging deploy is not "done" while the landing page still shows an older app build
than the code that was deployed. The start gate below still applies: the new build becomes the landing-page version
as soon as it has started on the tester's phone; if it can't start, the deploy is reported as incomplete and fixed —
never published around the gate.

## PERMANENT RULE — no build goes public until it has STARTED on a real phone (start gate)

2026-10-29: builds 1.0.4 (2013) and 1.0.5 (2014) passed every file check, went public, were installed on a phone —
and never started (not one request from them reached the server). File checks prove a build INSTALLS, not that it
RUNS. Therefore:

1. `tool/publish_apk.ps1` uploads the build to the hidden candidate slot and then WAITS (up to `-StartGateMinutes`,
   default 60) until THAT build reports `started` from a device — `GET api/public/app-release/android/canary?build=N`.
   The app sends `started` after its first screen is drawn (`lib/main.dart`). No switch skips the gate.
2. Any crash report from that build (native: `SmartWashApplication` crash handler, installed before any library
   initialises; Dart: `FlutterError.onError` / `PlatformDispatcher.onError`) fails the gate, prints the stack trace and
   NOTHING goes public. Crash reports are also logged by the API as `App CRASH report: …`.
3. The tester installs the candidate over the current app: open `…/download/android/candidate` (QR:
   `…/download/android/candidate/qr`), install, OPEN the app, wait for the first screen.
4. Only then is the candidate promoted to the landing page / QR / in-app update.
5. Native rule: nothing optional may run at process start (no auto-initialising libraries — WorkManager is
   initialised on demand via `SmartWashApplication`); every optional native feature is wrapped so its failure can't
   stop the app.
6. When this PC can run the emulator (enable Intel VT-x in the BIOS) the gate can be met by the emulator too.

## PERMANENT RULE — every release installs over the previous one (no uninstall)

Android installs a new APK over the installed app — keeping its data, settings and sign-in — only when ALL hold:
same **application id** (`com.cyberstackmedia.smartwash`), a signer the installed app trusts (the **release key**,
pin `tool/release-cert.sha256`) and a **higher versionCode**. For every release:

1. Bump `version: x.y.z+N` in `pubspec.yaml` (N above every published code; scripts refuse otherwise).
2. Write what changed in `tool/release-notes.json` (`en` + `ar`) — shown in the in-app update prompt.
3. `.\tool\build_release_apk.ps1 -Env staging` (`-Mandatory` or `-MinSupportedBuild N` when older builds must
   stop working; default = optional update).
4. `.\tool\publish_apk.ps1 -Env staging -SshKey …` — the gate checks the file downloaded from staging, then
   **`Test-UpdatesOver`** proves on the real files that it updates the live build in place (package, signer,
   versionCode) and, after promotion, that `api/public/app-release/android?build=<previous>` offers exactly this
   file (version, SHA-256, certificate, download). Any failure = nothing goes public.
5. Test on a phone/emulator when one exists (the gate installs `-r` over the live build automatically).
6. Never change the application id, never create a new key, never publish by hand. If a build cannot install over
   the previous one, fix that before calling it ready.

## In-app updates (from 1.0.3 / build 2012)

* Source of truth = the published `smartwash.json` (+ APK) in the downloads folder — the same files the landing page
  serves. The API reads it: `GET api/public/app-release/android?build=<installed>` → version, versionCode,
  `downloadUrl` (`api/public/app-release/android/file`, HTTPS), size, SHA-256, signing cert, notes (en/ar),
  `minSupportedVersionCode`, `updateAvailable`, `mandatory`. The server can force a minimum without rebuilding:
  configuration `MobileApp__Android__MinSupportedBuild` (raises, never above the published build).
* **Start-up**: the splash waits (≤ ~8 s) for the check before login / home. Optional → full-screen *Update Now* /
  *Later* (Later = until the next launch). Mandatory → no Later. Server unreachable → the app continues, unless an
  earlier check already said this build must update (remembered, so offline launches cannot skip it).
* **While open**: re-checked every 30 min and when the app returns to the foreground after 15 min; a new build is
  announced once with a dialog (Update Now / Later; mandatory has no Later).
* **Update Now** (`lib/features/update/`, native `AppUpdater.kt`): "Install unknown apps" permission (explained, opens
  the settings screen, continues automatically when the user returns) → free-space check → download with progress
  (cancellable) → verify SHA-256 + package + versionCode + minSdk + **same signing certificate as the installed app**
  → Android `PackageInstaller` session → Android's own confirmation. Cancel / failure → clear message + retry; the
  installed app is never touched until Android installs the new one. Nothing is installed silently (Android does
  not allow that for sideloaded apps).
* **After the update**: Android stops the old process and does not reopen the app; a "Smart Wash updated — tap to
  open" notification is posted (`PackageReplacedReceiver`). On the next start the app confirms the new build is
  running ("updated to version …"), then reopens the screen the user was on (bottom tab + driver task / order,
  stored as ids only) after re-checking it with the server — a reassigned task falls back to the task list. Data is
  reloaded fresh; no action is ever replayed. Sign-in survives the update (same app, secure storage kept).
* Builds before 2012 have no updater: those phones install 2012 once from the landing page (over the existing app,
  no uninstall); every later release arrives in the app.

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
| APK size | ~19 MB (64-bit) / ~17 MB (32-bit), one file per architecture, Dart obfuscated. The landing page's main button serves the 64-bit file (every phone since 2017); the 32-bit link under it is for old devices. Staging logs showed a 37 MB universal file taking 16 minutes on a tester's connection with the parallel connections dropping — size is the main cause of truncated downloads. |
| `build_release_apk.ps1`: "adb install FAILED" | The exact reason a phone would show as "App not installed" (`INSTALL_FAILED_UPDATE_INCOMPATIBLE` = different signing key on the device, `INSTALL_FAILED_VERSION_DOWNGRADE`, `INSTALL_PARSE_FAILED_NO_CERTIFICATES`, …). Fix the cause; never publish around it. |
| `build_release_apk.ps1`: "signed with the WRONG certificate" | `key.properties` points at a different keystore than the pinned one in `tool/release-cert.sha256`. Restore the original keystore; do not change the pin unless the key is being replaced on purpose. |
| `build_release_apk.ps1` / `publish_apk.ps1`: "already serves build N" | Bump `version: x.y.z+N` in `pubspec.yaml` — phones refuse to install a build number that is not higher than the installed one. |
| `publish_apk.ps1`: "PUBLIC DOWNLOAD DIFFERS" | Something between the server folder and the browser (proxy, cache, partial swap) altered the file. Nothing was handed to users that matches the build — fix the server path, re-run. |

## Sessions, notifications and Arabic (from 1.0.4 / build 2013)

* **Stay signed in:** tokens live in secure storage (Keystore) until sign-out. Refresh is single-flight
  (`ApiClient.refreshSession`): parallel 401s share ONE refresh — the server rejects a reused refresh token, which
  used to sign users out. A network error during refresh never signs out; only a rejected refresh token does.
  SignalR gets a refreshed token (`freshAccessToken`). The server session slides 7 days per refresh
  (`Jwt__RefreshTokenDays`).
* **Unread count / badge:** `lib/features/notifications/notification_center.dart` + native `AppNotifications.kt`
  (see the web repo's REALTIME.md). Badge = one silent summary notification whose number is the server count
  (dot on Pixel/stock launchers, number on Samsung and others, nothing on launchers without badges) + legacy
  BADGE_COUNT_UPDATE broadcast. App closed: WorkManager every ~15 min with a device token. POST_NOTIFICATIONS is
  requested after sign-in (Android 13+); if denied the in-app count still works.
* **Arabic:** every UI string goes through `context.t()` / `AppStrings` (l10n.dart); RTL comes from the locale.
  Phone / e-mail / code fields are LTR; `ltr(value)` isolates Latin values inside Arabic text. Server messages and
  notifications arrive translated (Accept-Language). Audit: run the l10n key check before a release — every
  `t('…')` literal must have an `_ar` entry.

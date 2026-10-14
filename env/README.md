# Build environments

One JSON file per environment, passed to Flutter with `--dart-define-from-file`.
They hold **only public, non-secret** values (the API host); never put keys or passwords here.

| File | Used for | API |
|---|---|---|
| `dev.json` | `flutter run` on the Android emulator against a local API | `http://10.0.2.2:5014` |
| `staging.json` | the downloadable staging APK (`tool/build_release_apk.ps1 -Env staging`) | `https://smartwash-staging-api.20-203-96-110.nip.io` |

Add `production.json` the same way when a production API exists. `lib/core/config.dart` is the only
place that reads these values; release builds refuse to start without an explicit HTTPS `API_BASE_URL`.

Real device + local API: `flutter run --dart-define=API_BASE_URL=http://<your-LAN-IP>:5014`.

# Smart Wash mobile app

Flutter app for laundry customers and drivers (one login, role-based experience) talking to `SmartWash.Api`.

* Run locally: `flutter run --dart-define-from-file=env/dev.json` (emulator -> local API on port 5014).
* Environments / API URL: `env/README.md` (`lib/core/config.dart` is the only reader).
* Android release, signing, direct-download publishing: `RELEASE.md`.
* Design system: `DESIGN_SYSTEM.md`.

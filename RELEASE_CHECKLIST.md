# Production Release Checklist

Before distributing a new APK release, complete all verification steps:

- [ ] Version updated in `pubspec.yaml`
- [ ] Version code increased in `pubspec.yaml`
- [ ] Production package ID verified (`com.example.solar_crm`)
- [ ] Production Firebase configuration verified (`google-services.json` in `android/app/`)
- [ ] Production Supabase configuration verified (`lib/core/constants/supabase_constants.dart`)
- [ ] Signing key available (`upload-keystore.jks`)
- [ ] `key.properties` configured in `android/key.properties`
- [ ] Keystore backed up securely (never committed to git)
- [ ] Debug banner disabled in release mode
- [ ] Static code analysis passed (`flutter analyze`)
- [ ] Release APK generated (`flutter build apk --release`)
- [ ] APK copied to `releases/Siya-Infotech-Solar-v1.0.0.apk`
- [ ] Latest link updated `releases/latest/Siya-Infotech-Solar-latest.apk`
- [ ] APK installed and launch tested on physical Android device
- [ ] Login flow tested
- [ ] Realtime notifications tested
- [ ] Database queries and updates tested
- [ ] Release webpage updated (`release-page/release.json`)
- [ ] Download links tested on download page
- [ ] `CHANGELOG.md` updated

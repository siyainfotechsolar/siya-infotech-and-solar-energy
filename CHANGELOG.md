# Changelog

All notable changes to the Siya Infotech & Solar Energy application will be documented in this file.

## v1.0.0 (2026-08-14)
- Initial production release for Siya Infotech & Solar Energy staff distribution.
- **Unified Directory**: Integrated Staff accounts and Temporary Worker contact list.
- **Customer & Lead CRM**: Full lifecycle tracking, search, age filters, and stage history.
- **Task Management**: Task creation, assignment, and global `NOT_COMPLETED` workflow with mandatory reasons.
- **Material Dispatch & Delivery**: Dispatch tracking, delivery assignment to Delivery Staff, photo upload proof, and status transitions.
- **Notification Infrastructure**: Supabase Realtime + FCM Push Notifications + Local Android Alerts.
- **Offline & Sync**: Real-time reconnection monitoring banner.

---

## Future Release Pattern
When creating future updates (e.g. `v1.0.1`):
1. Update `version: 1.0.1+2` in `pubspec.yaml`.
2. Run `scripts/release_android.bat` or `scripts/release_android.sh`.
3. Update `release.json` with new version details.
4. Add release notes to this file.

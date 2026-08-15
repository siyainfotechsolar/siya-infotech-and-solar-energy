import 'package:flutter_test/flutter_test.dart';
import 'package:solar_crm/core/services/app_update_service.dart';

void main() {
  group('AppReleaseInfo', () {
    test('parses optional release correctly', () {
      final map = {
        'id': 'rel-1',
        'app_name': 'Siya Solar Staff',
        'platform': 'android',
        'latest_version': '1.0.2',
        'latest_version_code': 3,
        'minimum_supported_version_code': 1,
        'apk_download_url': 'https://example.com/app.apk',
        'release_notes': '• Bug fixes\n• Task improvements',
        'update_type': 'OPTIONAL',
        'is_active': true,
      };

      final release = AppReleaseInfo.fromMap(map);
      expect(release.id, equals('rel-1'));
      expect(release.appName, equals('Siya Solar Staff'));
      expect(release.latestVersion, equals('1.0.2'));
      expect(release.latestVersionCode, equals(3));
      expect(release.minimumSupportedVersionCode, equals(1));
      expect(release.isMandatory, isFalse);
      expect(release.isActive, isTrue);
    });

    test('parses mandatory release correctly', () {
      final map = {
        'id': 'rel-2',
        'app_name': 'Siya Solar Staff',
        'platform': 'android',
        'latest_version': '2.0.0',
        'latest_version_code': 5,
        'minimum_supported_version_code': 4,
        'apk_download_url': 'https://example.com/app2.apk',
        'release_notes': 'Mandatory security update',
        'update_type': 'MANDATORY',
        'is_active': true,
      };

      final release = AppReleaseInfo.fromMap(map);
      expect(release.latestVersionCode, equals(5));
      expect(release.minimumSupportedVersionCode, equals(4));
      expect(release.isMandatory, isTrue);
    });
  });
}

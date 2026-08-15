import 'package:flutter/foundation.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

enum UpdateStatus {
  noUpdate,
  optionalUpdate,
  mandatoryUpdate,
}

class AppReleaseInfo {
  final String id;
  final String appName;
  final String platform;
  final String latestVersion;
  final int latestVersionCode;
  final int minimumSupportedVersionCode;
  final String apkDownloadUrl;
  final String releaseNotes;
  final bool isMandatory;
  final bool isActive;

  AppReleaseInfo({
    required this.id,
    required this.appName,
    required this.platform,
    required this.latestVersion,
    required this.latestVersionCode,
    required this.minimumSupportedVersionCode,
    required this.apkDownloadUrl,
    required this.releaseNotes,
    required this.isMandatory,
    required this.isActive,
  });

  factory AppReleaseInfo.fromMap(Map<String, dynamic> map) {
    final typeStr = (map['update_type'] as String? ?? 'OPTIONAL').toUpperCase();
    return AppReleaseInfo(
      id: map['id']?.toString() ?? '',
      appName: map['app_name'] as String? ?? 'Siya Solar Staff',
      platform: map['platform'] as String? ?? 'android',
      latestVersion: map['latest_version'] as String? ?? '1.0.0',
      latestVersionCode: (map['latest_version_code'] as num?)?.toInt() ?? 1,
      minimumSupportedVersionCode: (map['minimum_supported_version_code'] as num?)?.toInt() ?? 1,
      apkDownloadUrl: map['apk_download_url'] as String? ?? '',
      releaseNotes: map['release_notes'] as String? ?? '',
      isMandatory: typeStr == 'MANDATORY',
      isActive: map['is_active'] as bool? ?? true,
    );
  }
}

class AppUpdateCheckResult {
  final UpdateStatus status;
  final AppReleaseInfo? release;
  final int installedVersionCode;
  final String installedVersionName;

  AppUpdateCheckResult({
    required this.status,
    this.release,
    required this.installedVersionCode,
    required this.installedVersionName,
  });
}

class AppUpdateService {
  static Future<AppUpdateCheckResult> checkUpdate(SupabaseClient supabase) async {
    int installedVersionCode = 1;
    String installedVersionName = '1.0.0';

    try {
      final packageInfo = await PackageInfo.fromPlatform();
      installedVersionName = packageInfo.version;
      installedVersionCode = int.tryParse(packageInfo.buildNumber) ?? 1;
    } catch (e) {
      debugPrint('AppUpdateService: Error getting package info: $e');
    }

    try {
      // Query app_releases for active android release
      final response = await supabase
          .from('app_releases')
          .select()
          .eq('platform', 'android')
          .eq('is_active', true)
          .order('latest_version_code', ascending: false)
          .limit(1)
          .maybeSingle();

      if (response == null) {
        return AppUpdateCheckResult(
          status: UpdateStatus.noUpdate,
          installedVersionCode: installedVersionCode,
          installedVersionName: installedVersionName,
        );
      }

      final release = AppReleaseInfo.fromMap(Map<String, dynamic>.from(response));

      // Mandatory check: installed < minimum_supported_version_code OR (update_type == MANDATORY && installed < latest_version_code)
      if (installedVersionCode < release.minimumSupportedVersionCode ||
          (release.isMandatory && installedVersionCode < release.latestVersionCode)) {
        return AppUpdateCheckResult(
          status: UpdateStatus.mandatoryUpdate,
          release: release,
          installedVersionCode: installedVersionCode,
          installedVersionName: installedVersionName,
        );
      }

      // Optional check: installed < latest_version_code
      if (installedVersionCode < release.latestVersionCode) {
        return AppUpdateCheckResult(
          status: UpdateStatus.optionalUpdate,
          release: release,
          installedVersionCode: installedVersionCode,
          installedVersionName: installedVersionName,
        );
      }

      return AppUpdateCheckResult(
        status: UpdateStatus.noUpdate,
        release: release,
        installedVersionCode: installedVersionCode,
        installedVersionName: installedVersionName,
      );
    } catch (e) {
      debugPrint('AppUpdateService: Error checking app update: $e');
      // On network failure or error, allow normal app usage (no crash)
      return AppUpdateCheckResult(
        status: UpdateStatus.noUpdate,
        installedVersionCode: installedVersionCode,
        installedVersionName: installedVersionName,
      );
    }
  }
}

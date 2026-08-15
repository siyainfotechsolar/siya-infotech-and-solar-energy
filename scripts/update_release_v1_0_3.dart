import 'package:supabase/supabase.dart';
import '../lib/core/constants/supabase_constants.dart';

void main() async {
  final client = SupabaseClient(
    SupabaseConstants.supabaseUrl,
    SupabaseConstants.supabaseAnonKey,
  );

  final releaseData = {
    'app_name': 'Siya Solar Staff',
    'platform': 'android',
    'latest_version': '1.0.3',
    'latest_version_code': 4,
    'minimum_supported_version_code': 1,
    'apk_download_url': 'https://siyainfotechsolar.github.io/siya-infotech-and-solar-energy/releases/latest/Siya-Solar-Staff-latest.apk',
    'release_notes': 'v1.0.3: Official release with Global App Loading System and official Siya Infotech branding',
    'update_type': 'OPTIONAL',
    'is_active': true,
    'updated_at': DateTime.now().toIso8601String(),
  };

  try {
    // Check existing release
    final existing = await client
        .from('app_releases')
        .select('id')
        .eq('platform', 'android')
        .eq('is_active', true)
        .maybeSingle();

    if (existing != null) {
      await client
          .from('app_releases')
          .update(releaseData)
          .eq('id', existing['id']);
      print('Successfully updated existing app_releases record in Supabase!');
    } else {
      await client.from('app_releases').insert(releaseData);
      print('Successfully inserted new app_releases record in Supabase!');
    }
  } catch (e) {
    print('Supabase update_releases status: $e');
  }
}

import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../auth/providers/auth_provider.dart';
import '../../../core/utils/activity_logger.dart';

// ─── Fetch all 4 material rows for a customer (auto-seed if missing) ──────────
final siteMaterialsProvider = FutureProvider.autoDispose.family<
    List<Map<String, dynamic>>, String>((ref, customerId) async {
  final supabase = ref.watch(supabaseClientProvider);

  // 1. Fetch all products from products table
  final productsResponse = await supabase.from('products').select().order('name');
  final products = List<Map<String, dynamic>>.from(productsResponse);

  // 2. Fetch existing site materials for this site
  final response = await supabase
      .from('site_materials')
      .select('*, products(name)')
      .eq('site_id', customerId);

  List<Map<String, dynamic>> rows = List<Map<String, dynamic>>.from(response);

  final existingProductIds = rows.map((r) => r['product_id'] as String).toSet();
  final missingProducts = products.where((p) => !existingProductIds.contains(p['id'])).toList();

  if (missingProducts.isNotEmpty) {
    final userId = ref.read(currentUserProvider)?.id;
    final seeds = missingProducts.map((p) => {
      'site_id': customerId,
      'product_id': p['id'],
      'required_quantity': 0,
      'installed_quantity': 0,
      'status': p['name'] == 'Generation Meter' ? 'Not Required' : 'Not Started',
      if (userId case final id?) 'created_by': id,
    }).toList();

    final inserted = await supabase.from('site_materials').insert(seeds).select('*, products(name)');
    rows = [...rows, ...List<Map<String, dynamic>>.from(inserted)];
  }

  // Sort rows in the standard order: Structure, Solar Panel, Inverter, Generation Meter
  const order = ['Structure', 'Solar Panel', 'Inverter', 'Generation Meter'];
  rows.sort((a, b) {
    final nameA = ((a['products'] as Map?)?['name'] ?? '') as String;
    final nameB = ((b['products'] as Map?)?['name'] ?? '') as String;
    return order.indexOf(nameA).compareTo(order.indexOf(nameB));
  });

  return rows;
});

// ─── Update Site Material ─────────────────────────────────────────────────────
Future<void> updateSiteMaterial({
  required WidgetRef ref,
  required String materialId,
  required String customerId,
  required Map<String, dynamic> updates,
}) async {
  final supabase = ref.read(supabaseClientProvider);
  final userId = ref.read(currentUserProvider)?.id;

  final finalUpdates = {
    ...updates,
    'updated_at': DateTime.now().toUtc().toIso8601String(),
    if (userId case final id?) 'updated_by': id,
  };

  // 1. Fetch current material details to get product name for logging
  String productName = 'Material';
  try {
    final materialData = await supabase
        .from('site_materials')
        .select('*, products(name)')
        .eq('id', materialId)
        .maybeSingle();
    productName = ((materialData?['products'] as Map?)?['name'] ?? 'Material') as String;
  } catch (_) {}

  // 2. Perform the update
  await supabase.from('site_materials').update(finalUpdates).eq('id', materialId);

  // 3. Log staff activity
  if (userId != null) {
    try {
      final staffNameRes = await supabase.from('staff').select('name').eq('id', userId).maybeSingle();
      final staffName = staffNameRes?['name'] ?? 'Staff member';
      await ActivityLogger.log(
        supabase: supabase,
        customerId: customerId,
        action: 'material_updated',
        description: '$staffName updated material $productName information',
        performedBy: userId,
      );
    } catch (_) {}
  }

  ref.invalidate(siteMaterialsProvider(customerId));
}

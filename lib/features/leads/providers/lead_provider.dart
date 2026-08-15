import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../auth/providers/auth_provider.dart';

class LeadListNotifier extends AsyncNotifier<List<Map<String, dynamic>>> {
  @override
  Future<List<Map<String, dynamic>>> build() async {
    final supabase = ref.watch(supabaseClientProvider);
    final response = await supabase
        .from('leads')
        .select('*')
        .order('created_at', ascending: false)
        .limit(50);
    return List<Map<String, dynamic>>.from(response);
  }

  Future<void> upsertLead(String id) async {
    try {
      final supabase = ref.read(supabaseClientProvider);
      final response = await supabase.from('leads').select('*').eq('id', id).single();
      
      if (state.value != null) {
        final current = List<Map<String, dynamic>>.from(state.value!);
        final idx = current.indexWhere((l) => l['id'] == id);
        if (idx >= 0) {
          current[idx] = response;
        } else {
          current.insert(0, response);
        }
        state = AsyncData(current);
      }
    } catch (e) {
      // Handle or ignore if deleted before fetch
    }
  }

  void removeLead(String id) {
    if (state.value != null) {
      final current = state.value!.where((l) => l['id'] != id).toList();
      state = AsyncData(current);
    }
  }
}

final leadListProvider = AsyncNotifierProvider<LeadListNotifier, List<Map<String, dynamic>>>(LeadListNotifier.new);

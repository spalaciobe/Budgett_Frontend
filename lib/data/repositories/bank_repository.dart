
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/bank_model.dart';

class BankRepository {
  final SupabaseClient _supabase;

  BankRepository(this._supabase);

  Future<List<Bank>> getBanks() async {
    try {
      print('DEBUG: Fetching banks from Supabase...');
      final response = await _supabase.from('bancos').select();
      final data = response as List<dynamic>;
      print('DEBUG: Banks found: ${data.length}');
      return data.map((json) => Bank.fromJson(json)).toList();
    } catch (e) {
      print('DEBUG: Error fetching banks: $e');
      rethrow;
    }
  }
}

final bankRepositoryProvider = Provider<BankRepository>((ref) {
  return BankRepository(Supabase.instance.client);
});

final banksFutureProvider = FutureProvider<List<Bank>>((ref) async {
  return ref.read(bankRepositoryProvider).getBanks();
});

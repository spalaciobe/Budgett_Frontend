import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/broker_model.dart';

class BrokerRepository {
  final SupabaseClient _supabase;

  BrokerRepository(this._supabase);

  Future<List<Broker>> getBrokers() async {
    final response = await _supabase.from('brokers').select().eq('activo', true).order('nombre');
    final data = response as List<dynamic>;
    return data.map((json) => Broker.fromJson(json)).toList();
  }
}

final brokerRepositoryProvider = Provider<BrokerRepository>((ref) {
  return BrokerRepository(Supabase.instance.client);
});

final brokersFutureProvider = FutureProvider<List<Broker>>((ref) async {
  return ref.read(brokerRepositoryProvider).getBrokers();
});

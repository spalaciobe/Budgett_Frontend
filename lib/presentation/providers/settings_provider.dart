import 'package:flutter_riverpod/flutter_riverpod.dart';

// Simple settings provider (in memory for now, TODO: Persist)
final currencyProvider = StateProvider<String>((ref) => 'USD');
final themeModeProvider = StateProvider<bool>((ref) => false); // false = light, true = dark

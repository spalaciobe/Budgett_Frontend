import 'package:flutter/material.dart';

class IconHelper {
  static const Map<String, IconData> iconMap = {
    // Finance / General
    'category': Icons.category,
    'attach_money': Icons.attach_money,
    'savings': Icons.savings,
    'credit_card': Icons.credit_card,
    'account_balance': Icons.account_balance,
    'receipt_long': Icons.receipt_long,
    
    // Living
    'home': Icons.home,
    'apartment': Icons.apartment,
    'bolt': Icons.bolt, // Utilities
    'water_drop': Icons.water_drop,
    'wifi': Icons.wifi,
    
    // Transport
    'directions_car': Icons.directions_car,
    'directions_bus': Icons.directions_bus,
    'local_gas_station': Icons.local_gas_station,
    'flight': Icons.flight,
    'commute': Icons.commute,

    // Food
    'restaurant': Icons.restaurant,
    'local_cafe': Icons.local_cafe,
    'local_pizza': Icons.local_pizza,
    'fastfood': Icons.fastfood,
    'kitchen': Icons.kitchen, // Groceries

    // Personal & Health
    'person': Icons.person,
    'health_and_safety': Icons.health_and_safety,
    'fitness_center': Icons.fitness_center,
    'medical_services': Icons.medical_services,
    'self_improvement': Icons.self_improvement,
    'checkroom': Icons.checkroom, // Clothing

    // Entertainment
    'movie': Icons.movie,
    'confirmation_number': Icons.confirmation_number, // Tickets
    'sports_esports': Icons.sports_esports,
    'music_note': Icons.music_note,
    'subscriptions': Icons.subscriptions,

    // Others
    'shopping_bag': Icons.shopping_bag,
    'shopping_cart': Icons.shopping_cart,
    'card_giftcard': Icons.card_giftcard,
    'school': Icons.school,
    'pets': Icons.pets,
    'more_horiz': Icons.more_horiz,
    'work': Icons.work,
    
    // Additions for Goals & Expanded Categories
    'flag': Icons.flag,
    'diamond': Icons.diamond,
    'beach_access': Icons.beach_access,
    'smartphone': Icons.smartphone,
    'computer': Icons.computer,
    'camera_alt': Icons.camera_alt,
    'videogame_asset': Icons.videogame_asset,
    'menu_book': Icons.menu_book,
    'palette': Icons.palette,
    'child_care': Icons.child_care,
    'build': Icons.build,
    'mic': Icons.mic,
    'local_bar': Icons.local_bar,
  };

  static IconData getIcon(String? name) {
    if (name == null) return Icons.category;
    return iconMap[name] ?? Icons.category;
  }

  static String getIconName(IconData icon) {
    // Reverse lookup
    return iconMap.entries.firstWhere((element) => element.value == icon, orElse: () => const MapEntry('category', Icons.category)).key;
  }

  static bool isValidIcon(String? name) {
    if (name == null) return false;
    return iconMap.containsKey(name);
  }
}

import 'package:budgett_frontend/data/models/sub_category_model.dart';

class Category {
  final String id;
  final String name;
  final String type; // 'income' or 'expense'
  final String? icon;
  final String? color;
  final List<SubCategory>? subCategories;

  Category({
    required this.id,
    required this.name,
    required this.type,
    this.icon,
    this.color,
    this.subCategories,
  });

  factory Category.fromJson(Map<String, dynamic> json) {
    return Category(
      id: json['id'],
      name: json['name'],
      type: json['type'],
      icon: json['icon'],
      color: json['color'],
      subCategories: json['sub_categories'] != null
          ? (json['sub_categories'] as List)
              .map((i) => SubCategory.fromJson(i))
              .toList()
          : [],
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      'type': type,
      'icon': icon,
      'color': color,
      // We generally don't send subCategories back when creating/updating a category this way directly,
      // but keeping it consistent if needed.
    };
  }
}

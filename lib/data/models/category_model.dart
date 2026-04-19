import 'package:budgett_frontend/data/models/sub_category_model.dart';

class Category {
  final String id;
  final String name;
  final String type; // 'income', 'expense', 'savings'
  final String? icon;
  final String? color;
  final String? targetAccountId; // savings categories: optional physical destination
  final List<SubCategory>? subCategories;

  Category({
    required this.id,
    required this.name,
    required this.type,
    this.icon,
    this.color,
    this.targetAccountId,
    this.subCategories,
  });

  bool get isSavings => type == 'savings';
  bool get isExpense => type == 'expense';
  bool get isIncome => type == 'income';

  factory Category.fromJson(Map<String, dynamic> json) {
    return Category(
      id: json['id'],
      name: json['name'],
      type: json['type'],
      icon: json['icon'],
      color: json['color'],
      targetAccountId: json['target_account_id'] as String?,
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
      'target_account_id': targetAccountId,
    };
  }
}

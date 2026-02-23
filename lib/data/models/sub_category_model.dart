class SubCategory {
  final String id;
  final String categoryId;
  final String name;

  SubCategory({
    required this.id,
    required this.categoryId,
    required this.name,
  });

  factory SubCategory.fromJson(Map<String, dynamic> json) {
    return SubCategory(
      id: json['id'],
      categoryId: json['category_id'],
      name: json['name'],
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'category_id': categoryId,
      'name': name,
    };
  }
}

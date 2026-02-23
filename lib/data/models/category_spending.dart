class CategorySpending {
  double total;
  final Map<String, double> subCategories;

  CategorySpending({
    this.total = 0.0, 
    Map<String, double>? subCategories,
  }) : subCategories = subCategories ?? {};
}

import 'package:budgett_frontend/core/parsing/text_normalizer.dart';

/// The learning memory of the capture pipeline.
///
/// One row says: "whenever a message's merchant looks like [pattern], call it
/// [displayName], file it under [categoryId], and (if [autoPost]) do it without
/// asking me again."
///
/// [pattern] is always a `normalizeMerchant`-normalised string so the same key
/// the parser produces can be looked up directly.
class MerchantAlias {
  final String id;
  final String matchType; // exact | contains | regex
  final String pattern;
  final String displayName;
  final String? categoryId;
  final String? subCategoryId;
  final String? expenseGroupId;
  final String? accountId;
  final String? movementType;
  final bool autoPost;
  final int priority;
  final int hitCount;
  final DateTime? lastUsedAt;

  const MerchantAlias({
    required this.id,
    required this.pattern,
    required this.displayName,
    this.matchType = 'exact',
    this.categoryId,
    this.subCategoryId,
    this.expenseGroupId,
    this.accountId,
    this.movementType,
    this.autoPost = false,
    this.priority = 100,
    this.hitCount = 0,
    this.lastUsedAt,
  });

  /// True when this alias applies to [merchantKey] (already normalised).
  bool matches(String? merchantKey) {
    if (merchantKey == null || merchantKey.isEmpty) return false;
    switch (matchType) {
      case 'contains':
        return merchantKey.contains(pattern);
      case 'regex':
        try {
          return RegExp(pattern, caseSensitive: false).hasMatch(merchantKey);
        } on FormatException {
          // A malformed pattern must not break ingestion of every message.
          return false;
        }
      case 'exact':
      default:
        return merchantKey == pattern;
    }
  }

  /// True when the alias carries enough classification for a message matching
  /// it to be posted unattended.
  bool get isComplete => categoryId != null;

  factory MerchantAlias.fromJson(Map<String, dynamic> json) => MerchantAlias(
        id: json['id'] as String,
        matchType: (json['match_type'] as String?) ?? 'exact',
        pattern: json['pattern'] as String,
        displayName: json['display_name'] as String,
        categoryId: json['category_id'] as String?,
        subCategoryId: json['sub_category_id'] as String?,
        expenseGroupId: json['expense_group_id'] as String?,
        accountId: json['account_id'] as String?,
        movementType: json['movement_type'] as String?,
        autoPost: (json['auto_post'] as bool?) ?? false,
        priority: (json['priority'] as int?) ?? 100,
        hitCount: (json['hit_count'] as int?) ?? 0,
        lastUsedAt: json['last_used_at'] != null
            ? DateTime.parse(json['last_used_at'] as String).toLocal()
            : null,
      );

  /// Picks the alias that should win for [merchantKey].
  ///
  /// Lower [priority] first; ties break towards the longer pattern, so a
  /// specific rule ("EXITO SUPER CL 80") beats a broad one ("EXITO").
  static MerchantAlias? bestMatch(
      List<MerchantAlias> aliases, String? merchantKey) {
    final matches =
        aliases.where((alias) => alias.matches(merchantKey)).toList();
    if (matches.isEmpty) return null;
    matches.sort((a, b) {
      final byPriority = a.priority.compareTo(b.priority);
      if (byPriority != 0) return byPriority;
      return b.pattern.length.compareTo(a.pattern.length);
    });
    return matches.first;
  }

  /// Default friendly name to offer when no alias exists yet.
  static String suggestDisplayName(String? merchantRaw, String? merchantKey) {
    final key = merchantKey ?? '';
    if (key.isNotEmpty) return prettifyMerchant(key);
    return (merchantRaw ?? '').trim();
  }
}

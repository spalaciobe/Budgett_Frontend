import 'package:budgett_frontend/core/parsing/expense_message_parser.dart';
import 'package:budgett_frontend/core/parsing/message_kind.dart';
import 'package:budgett_frontend/core/utils/capture_dedup.dart';

/// A message captured from a notification or SMS, with whatever the parser
/// could make of it. Rows live in `captured_messages` and double as the
/// review inbox and the audit trail for every auto-posted expense.
class CapturedMessage {
  final String id;
  final String? sourceId;
  final String channel; // notification | sms
  final String sourceKey;

  final String? title;
  final String body;
  final DateTime receivedAt;
  final DateTime occurredAt;

  // GPS fix taken natively at the moment the message arrived.
  final double? latitude;
  final double? longitude;
  final double? locationAccuracyM;
  final String? locationLabel;

  final String parseStatus; // parsed | unparsed | ignored
  final String? issuerKey;
  final String? merchantRaw;
  final String? merchantDisplay;
  final double? amount;
  final String? currency;
  final String? cardLast4;
  final MessageKind? kind;
  final double? confidence;
  final String? matchedAliasId;

  final String status; // pending | posted | duplicate | dismissed | failed
  final String? transactionId;
  final String? duplicateOf;
  final String? dedupHashValue;
  final String fingerprint;
  final String? error;

  const CapturedMessage({
    required this.id,
    required this.channel,
    required this.sourceKey,
    required this.body,
    required this.receivedAt,
    required this.occurredAt,
    required this.fingerprint,
    this.sourceId,
    this.title,
    this.latitude,
    this.longitude,
    this.locationAccuracyM,
    this.locationLabel,
    this.parseStatus = 'unparsed',
    this.issuerKey,
    this.merchantRaw,
    this.merchantDisplay,
    this.amount,
    this.currency,
    this.cardLast4,
    this.kind,
    this.confidence,
    this.matchedAliasId,
    this.status = 'pending',
    this.transactionId,
    this.duplicateOf,
    this.dedupHashValue,
    this.error,
  });

  bool get hasLocation => latitude != null && longitude != null;
  bool get isPending => status == 'pending';
  bool get isPosted => status == 'posted';
  bool get isDuplicate => status == 'duplicate';

  /// Name to show for the movement: the alias if one matched, else the raw
  /// merchant text, else the message title.
  String get headline {
    final display = merchantDisplay?.trim();
    if (display != null && display.isNotEmpty) return display;
    final raw = merchantRaw?.trim();
    if (raw != null && raw.isNotEmpty) return raw;
    final t = title?.trim();
    if (t != null && t.isNotEmpty) return t;
    return 'Unrecognised message';
  }

  /// Comparison shape used by the deduplicator.
  DedupCandidate toDedupCandidate({String? merchantKey}) => DedupCandidate(
        id: id,
        amount: amount ?? 0,
        currency: currency ?? 'COP',
        merchantKey: merchantKey,
        cardLast4: cardLast4,
        issuerKey: issuerKey,
        occurredAt: occurredAt,
      );

  factory CapturedMessage.fromJson(Map<String, dynamic> json) =>
      CapturedMessage(
        id: json['id'] as String,
        sourceId: json['source_id'] as String?,
        channel: json['channel'] as String,
        sourceKey: json['source_key'] as String,
        title: json['title'] as String?,
        body: json['body'] as String? ?? '',
        receivedAt: DateTime.parse(json['received_at'] as String).toLocal(),
        occurredAt: json['occurred_at'] != null
            ? DateTime.parse(json['occurred_at'] as String).toLocal()
            : DateTime.parse(json['received_at'] as String).toLocal(),
        latitude: (json['latitude'] as num?)?.toDouble(),
        longitude: (json['longitude'] as num?)?.toDouble(),
        locationAccuracyM: (json['location_accuracy_m'] as num?)?.toDouble(),
        locationLabel: json['location_label'] as String?,
        parseStatus: json['parse_status'] as String? ?? 'unparsed',
        issuerKey: json['issuer_key'] as String?,
        merchantRaw: json['merchant_raw'] as String?,
        merchantDisplay: json['merchant_display'] as String?,
        amount: (json['amount'] as num?)?.toDouble(),
        currency: json['currency'] as String?,
        cardLast4: json['card_last4'] as String?,
        kind: MessageKind.fromWire(json['kind'] as String?),
        confidence: (json['confidence'] as num?)?.toDouble(),
        matchedAliasId: json['matched_alias_id'] as String?,
        status: json['status'] as String? ?? 'pending',
        transactionId: json['transaction_id'] as String?,
        duplicateOf: json['duplicate_of'] as String?,
        dedupHashValue: json['dedup_hash'] as String?,
        fingerprint: json['fingerprint'] as String? ?? '',
        error: json['error'] as String?,
      );
}

/// A message straight off the native queue, before parsing.
class RawCapture {
  final String channel; // notification | sms
  final String sourceKey; // package name or SMS sender
  final String? sourceName; // app label, when Android could resolve it
  final String? title;
  final String body;
  final DateTime receivedAt;
  final double? latitude;
  final double? longitude;
  final double? locationAccuracyM;

  const RawCapture({
    required this.channel,
    required this.sourceKey,
    required this.body,
    required this.receivedAt,
    this.sourceName,
    this.title,
    this.latitude,
    this.longitude,
    this.locationAccuracyM,
  });

  /// Stable identity of this exact capture, so draining the native queue more
  /// than once cannot create two rows. Unique per user in the database.
  String get fingerprint => [
        channel,
        sourceKey,
        receivedAt.millisecondsSinceEpoch,
        _fnv1a(body),
      ].join('|');

  factory RawCapture.fromPlatform(Map<dynamic, dynamic> map) {
    final millis = (map['receivedAt'] as num?)?.toInt() ??
        DateTime.now().millisecondsSinceEpoch;
    return RawCapture(
      channel: map['channel'] as String? ?? 'notification',
      sourceKey: map['sourceKey'] as String? ?? 'unknown',
      sourceName: map['sourceName'] as String?,
      title: map['title'] as String?,
      body: map['body'] as String? ?? '',
      receivedAt: DateTime.fromMillisecondsSinceEpoch(millis),
      latitude: (map['latitude'] as num?)?.toDouble(),
      longitude: (map['longitude'] as num?)?.toDouble(),
      locationAccuracyM: (map['locationAccuracy'] as num?)?.toDouble(),
    );
  }
}

/// FNV-1a, 64-bit, hex. Deterministic across runs and platforms — unlike
/// `String.hashCode`, which Dart does not guarantee to be stable.
String _fnv1a(String input) {
  const offsetBasis = 0xcbf29ce484222325;
  const prime = 0x100000001b3;
  var hash = offsetBasis;
  for (final unit in input.codeUnits) {
    hash ^= unit;
    hash = (hash * prime) & 0xFFFFFFFFFFFFFFFF;
  }
  return hash.toRadixString(16).padLeft(16, '0');
}

/// Convenience view over a parsed message plus the alias that matched it,
/// carried from the ingest pipeline into the inbox UI.
class CaptureSuggestion {
  final ParsedMessage parsed;
  final String? merchantDisplay;
  final String? accountId;
  final String? categoryId;
  final String? subCategoryId;
  final String? expenseGroupId;
  final String? movementType;
  final String? matchedAliasId;
  final DuplicateVerdict? duplicate;
  final bool canAutoPost;

  const CaptureSuggestion({
    required this.parsed,
    this.merchantDisplay,
    this.accountId,
    this.categoryId,
    this.subCategoryId,
    this.expenseGroupId,
    this.movementType,
    this.matchedAliasId,
    this.duplicate,
    this.canAutoPost = false,
  });
}

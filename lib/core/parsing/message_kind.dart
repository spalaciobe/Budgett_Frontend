/// What a bank message says happened, and how that maps onto a Budgett
/// transaction.
library;

enum MessageKind {
  /// Card purchase / POS / online payment. The bread-and-butter case.
  purchase,

  /// ATM cash withdrawal or credit-card cash advance.
  withdrawal,

  /// Money leaving the account towards someone else.
  transferOut,

  /// Money arriving.
  transferIn,

  /// A credit-card payment (the user paying down the card).
  payment,

  /// Reversal / chargeback / voided purchase.
  refund,

  /// Attempt the bank rejected. Never a movement — captured for the record.
  declined;

  /// Wire value stored in `captured_messages.kind`.
  String get wireName => switch (this) {
        MessageKind.purchase => 'purchase',
        MessageKind.withdrawal => 'withdrawal',
        MessageKind.transferOut => 'transfer_out',
        MessageKind.transferIn => 'transfer_in',
        MessageKind.payment => 'payment',
        MessageKind.refund => 'refund',
        MessageKind.declined => 'declined',
      };

  static MessageKind? fromWire(String? value) => switch (value) {
        'purchase' => MessageKind.purchase,
        'withdrawal' => MessageKind.withdrawal,
        'transfer_out' => MessageKind.transferOut,
        'transfer_in' => MessageKind.transferIn,
        'payment' => MessageKind.payment,
        'refund' => MessageKind.refund,
        'declined' => MessageKind.declined,
        _ => null,
      };

  /// Label shown in the capture inbox.
  String get label => switch (this) {
        MessageKind.purchase => 'Purchase',
        MessageKind.withdrawal => 'Withdrawal',
        MessageKind.transferOut => 'Transfer out',
        MessageKind.transferIn => 'Transfer in',
        MessageKind.payment => 'Card payment',
        MessageKind.refund => 'Refund',
        MessageKind.declined => 'Declined',
      };

  /// `transactions.type` this kind becomes.
  String get transactionType => switch (this) {
        MessageKind.purchase => 'expense',
        MessageKind.withdrawal => 'expense',
        MessageKind.transferOut => 'expense',
        MessageKind.transferIn => 'income',
        MessageKind.payment => 'transfer',
        MessageKind.refund => 'income',
        MessageKind.declined => 'expense',
      };

  /// Suggested `transactions.movement_type`.
  String? get movementType => switch (this) {
        MessageKind.purchase => 'variable',
        MessageKind.withdrawal => 'variable',
        MessageKind.transferOut => 'variable',
        MessageKind.transferIn => 'income',
        MessageKind.payment => 'transfer',
        MessageKind.refund => 'reimbursement',
        MessageKind.declined => null,
      };

  /// Whether this kind may ever be posted without the user looking at it.
  ///
  /// [transferOut] counts: it becomes `type='expense'` and needs no
  /// destination account, so there is nothing left to ask about once an alias
  /// supplies the account and category. Excluding it only meant that Bre-B
  /// keys, account transfers and QR — most of what a Colombian account
  /// actually pays with — could never be automated.
  ///
  /// [payment] stays out because a card payment is a real two-leg transfer
  /// between accounts, and the far leg cannot be derived from one line.
  bool get isAutoPostable =>
      this == MessageKind.purchase ||
      this == MessageKind.withdrawal ||
      this == MessageKind.transferOut;
}

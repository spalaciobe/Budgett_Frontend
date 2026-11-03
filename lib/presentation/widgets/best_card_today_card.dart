import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:budgett_frontend/core/app_spacing.dart';
import 'package:budgett_frontend/core/app_text.dart';
import 'package:budgett_frontend/core/app_theme.dart';
import 'package:budgett_frontend/core/utils/card_recommendation.dart';

/// Which credit card to pay with today: the one whose bill for a purchase made
/// now comes due last. Same ranking as the home-screen widget.
///
/// Takes the ranking rather than watching a provider so Home decides whether
/// there is anything to show at all — with no credit cards this card is not
/// rendered, and on a phone that also means there is nothing to swipe to.
class BestCardTodayCard extends StatelessWidget {
  final CardRecommendationStatus status;
  final List<CardRecommendation> ranked;

  /// How many cards to list under the best one.
  final int maxRunnersUp;

  const BestCardTodayCard({
    super.key,
    required this.status,
    required this.ranked,
    this.maxRunnersUp = 2,
  });

  static final _due = DateFormat('EEE, MMM d', 'en_US');

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    if (status != CardRecommendationStatus.ok || ranked.isEmpty) {
      return Card(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Best card today',
                  style: AppText.label.copyWith(color: context.muted)),
              kGapSm,
              Text(
                'Add cut-off and payment days to your credit cards to see '
                'which one gives you the most time to pay.',
                style: AppText.subtitle,
              ),
              Align(
                alignment: Alignment.centerRight,
                child: TextButton(
                  onPressed: () => context.go('/accounts'),
                  child: const Text('Set up cards'),
                ),
              ),
            ],
          ),
        ),
      );
    }

    final best = ranked.first;
    final runnersUp = ranked.skip(1).take(maxRunnersUp).toList();
    final canOpen = !best.account.isPocket;

    return Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: canOpen
            ? () => context.push('/credit-card/${best.account.id}')
            : null,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text('Best card today',
                        style: AppText.label.copyWith(color: context.muted)),
                  ),
                  Icon(Icons.credit_card, size: 16, color: context.muted),
                ],
              ),
              kGapSm,
              Text(
                best.account.name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: AppText.cardName.copyWith(fontSize: 17),
              ),
              kGapXs,
              // The figure is the answer; the due date is its proof.
              Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    '${best.daysToPay}',
                    style: AppText.balanceHero.copyWith(color: context.positive),
                  ),
                  const SizedBox(width: kSpaceMd),
                  Expanded(
                    child: Padding(
                      padding: const EdgeInsets.only(bottom: 4),
                      child: Text(
                        best.daysToPay == 1 ? 'day to pay' : 'days to pay',
                        style: AppText.caption.copyWith(color: context.muted),
                      ),
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.only(bottom: 4),
                    child: Text(
                      'Due ${_due.format(best.payment)}',
                      style: AppText.caption.copyWith(
                        color: theme.colorScheme.onSurface,
                      ),
                    ),
                  ),
                ],
              ),
              if (runnersUp.isNotEmpty) ...[
                kGapMd,
                Divider(height: 1, color: theme.dividerTheme.color),
                kGapMd,
                for (final r in runnersUp)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: kSpaceXs),
                    child: Row(
                      children: [
                        Expanded(
                          child: Text(
                            r.account.name,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: AppText.caption,
                          ),
                        ),
                        const SizedBox(width: kSpaceLg),
                        Text(
                          '${r.daysToPay} days',
                          style: AppText.caption.copyWith(
                            color: context.muted,
                            fontFeatures: const [FontFeature.tabularFigures()],
                          ),
                        ),
                      ],
                    ),
                  ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

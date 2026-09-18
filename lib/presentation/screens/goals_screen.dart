import 'package:flutter/material.dart';
import 'package:budgett_frontend/presentation/widgets/empty_state.dart';
import 'package:budgett_frontend/core/utils/error_messages.dart';
import 'package:budgett_frontend/core/app_spacing.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:budgett_frontend/presentation/providers/finance_provider.dart';
import 'package:budgett_frontend/presentation/widgets/add_goal_dialog.dart';
import 'package:budgett_frontend/presentation/utils/currency_formatter.dart';
import 'package:budgett_frontend/presentation/widgets/edit_goal_dialog.dart';
import 'package:budgett_frontend/presentation/utils/icon_helper.dart';
import '../../core/app_theme.dart';
import '../../core/app_text.dart';
import '../widgets/skeleton.dart';
import '../widgets/page_body.dart';
import '../widgets/screen_title.dart';

class GoalsScreen extends ConsumerWidget {
  const GoalsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final goalsAsync = ref.watch(goalsProvider);

    return Scaffold(
      appBar: AppBar(title: ScreenTitle('Financial Goals')),
      body: RefreshIndicator(
        onRefresh: () async {
          ref.invalidate(goalsProvider);
          await ref.read(goalsProvider.future);
        },
        child: goalsAsync.when(
        data: (goals) {
          if (goals.isEmpty) {
            return const EmptyState(
              icon: Icons.flag_outlined,
              title: 'No goals yet',
              message: 'Set a savings goal with the + button.',
            );
          }
          return PageBody(
            maxWidth: kColumnMaxWidth,
            child: ListView.separated(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: kScreenPaddingWithFab,
            itemCount: goals.length,
            separatorBuilder: (context, index) => kGapLg,
            itemBuilder: (context, index) {
              final goal = goals[index];
              
              // Timeline calculations
              final now = DateTime.now();
              final createdAt = goal.createdAt; 
              final deadline = goal.deadline;

              int monthsElapsed = 0;
              int totalMonths = 0;
              double expectedAmount = 0.0;
              double monthlySavings = 0.0;
              String timeInfo = '';
              double expectedProgress = 0.0;

              if (deadline != null) {
                final totalDays = deadline.difference(createdAt).inDays;
                final elapsedDays = now.difference(createdAt).inDays;
                final remainingDays = deadline.difference(now).inDays;

                final effectiveTotalDays = totalDays <= 0 ? 1 : totalDays;
                final effectiveRemainingMonths = (remainingDays / 30).ceil();
                final safeRemainingMonths = effectiveRemainingMonths <= 0 ? 1 : effectiveRemainingMonths;

                totalMonths = (totalDays / 30).ceil();
                if (totalMonths < 1) totalMonths = 1;

                monthsElapsed = (elapsedDays / 30).floor() + 1; // Start at Month 1
                if (monthsElapsed < 1) monthsElapsed = 1; // Ensure minimum is 1
                if (monthsElapsed > totalMonths) monthsElapsed = totalMonths; // Cap at max
                
                // Quantize expected progress to months (Month 1 = 1 unit of progress)
                expectedProgress = (monthsElapsed / totalMonths).clamp(0.0, 1.0);
                expectedAmount = expectedProgress * goal.targetAmount;
                
                // Ensure expectedProgress is not NaN
                if (expectedProgress.isNaN) expectedProgress = 0.0;

                final remainingAmount = goal.targetAmount - goal.currentAmount;
                monthlySavings = remainingAmount > 0 ? remainingAmount / safeRemainingMonths : 0.0;
                
                timeInfo = 'Month $monthsElapsed of $totalMonths';
              } else {
                 timeInfo = 'Ongoing';
              }

              final double progress = goal.targetAmount > 0 
                  ? (goal.currentAmount / goal.targetAmount).clamp(0.0, 1.0) 
                  : 0.0;
              
              final isMaterialIcon = IconHelper.isValidIcon(goal.iconName);

              return Card(
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(kCardRadius)),
                child: InkWell(
                  onTap: () {
                    showDialog(
                      context: context,
                      builder: (context) => EditGoalDialog(goal: goal),
                    );
                  },
                  child: Padding(
                    padding: kCardPadding,
                    // The timeline panel is 150px wide. Beside a 48px avatar on
                    // a 390px screen that left ~124px for the goal's name and
                    // amounts, so every one of them truncated. Below ~520px it
                    // moves under the row and gets the full width instead.
                    child: LayoutBuilder(
                      builder: (context, cardConstraints) {
                    final wide = cardConstraints.maxWidth >= 520;
                    final Widget? timelinePanel = deadline == null
                        ? null
                        : _GoalTimelinePanel(
                            wide: wide,
                            timeInfo: timeInfo,
                            monthlySavings: monthlySavings,
                            expectedAmount: expectedAmount,
                            currentAmount: goal.currentAmount,
                          );
                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: [
                        CircleAvatar(
                          radius: 24,
                          backgroundColor: Theme.of(context).colorScheme.primaryContainer,
                          child: isMaterialIcon 
                            ? Icon(
                                IconHelper.getIcon(goal.iconName),
                                size: 28,
                                color: Theme.of(context).colorScheme.onPrimaryContainer,
                              )
                            : Text(
                                goal.iconName ?? '🎯',
                                style: AppText.balance,
                              ),
                        ),
                        const SizedBox(width: 16),
                        
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                goal.name,
                                style: AppText.sectionTitle,
                                maxLines: 1,
                                overflow: TextOverflow.fade,
                              ),
                              const SizedBox(height: 4),
                              Text.rich(
                                TextSpan(
                                  children: [
                                    TextSpan(
                                      text: CurrencyFormatter.format(goal.currentAmount),
                                      style: TextStyle(
                                        color: Theme.of(context).colorScheme.primary,
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                    TextSpan(
                                      text: ' / ${CurrencyFormatter.format(goal.targetAmount)}',
                                      style: AppText.subtitle.copyWith(color: context.muted),
                                    ),
                                  ],
                                ),
                                maxLines: 1,
                                overflow: TextOverflow.fade,
                              ),
                              const SizedBox(height: 8),
                              Stack(
                                children: [
                                  LinearProgressIndicator(
                                    value: 1, // Full background
                                    backgroundColor: Colors.transparent,
                                    color: context.muted.withValues(alpha: 0.18),
                                    minHeight: 10,
                                    borderRadius: BorderRadius.circular(5),
                                  ),
                                  if (deadline != null && expectedProgress > 0)
                                    // Expected Progress Marker (Ghost bar)
                                    FractionallySizedBox(
                                      widthFactor: expectedProgress,
                                      child: Stack(
                                        children: [
                                          Container(
                                            height: 10,
                                            decoration: BoxDecoration(
                                              color: context.positive.withValues(alpha: 0.3),
                                              borderRadius: BorderRadius.circular(5),
                                            ),
                                          ),
                                          // Dashed line at right edge
                                          Positioned(
                                            right: 0,
                                            top: 0,
                                            bottom: 0,
                                            child: CustomPaint(
                                              size: const Size(2, 10),
                                              painter: _DottedVerticalLinePainter(
                                                color: Colors.black.withValues(alpha: 0.35),
                                              ),
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                  LinearProgressIndicator(
                                    value: progress,
                                    backgroundColor: Colors.transparent,
                                    color: Theme.of(context).colorScheme.primary,
                                    minHeight: 10,
                                    borderRadius: BorderRadius.circular(5),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 4),
                              Text(
                                '${(progress * 100).toStringAsFixed(0)}% completed',
                                style: Theme.of(context).textTheme.bodySmall,
                              ),
                            ],
                          ),
                        ),
                        
                        if (wide && timelinePanel != null) timelinePanel,
                      ],
                    ),
                    if (!wide && timelinePanel != null) ...[
                      kGapXl,
                      timelinePanel,
                    ],
                      ],
                    );
                      },
                    ),
                  ),
                ),
              );
            },
          ),
          );
        },
        loading: () => const SkeletonCards(),
        error: (err, stack) => Center(child: Text(friendlyError(err))),
        ),
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () {
          showDialog(
            context: context,
            builder: (context) => const AddGoalDialog(),
          );
        },
        child: const Icon(Icons.add),
      ),
    );
  }
}

// Custom painter for dotted vertical line
class _DottedVerticalLinePainter extends CustomPainter {
  final Color color;
  
  _DottedVerticalLinePainter({required this.color});
  
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = 2
      ..style = PaintingStyle.fill;
    
    const dotRadius = 1.0;
    const dotSpacing = 3.0;
    double startY = dotRadius;
    
    while (startY < size.height) {
      canvas.drawCircle(
        Offset(size.width / 2, startY),
        dotRadius,
        paint,
      );
      startY += dotSpacing;
    }
  }
  
  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

/// The deadline panel on a goal card: where the goal should be by now, and
/// whether it is.
///
/// Sits beside the goal on a wide card and underneath it on a narrow one —
/// at 150px fixed beside a 48px avatar it used to leave the goal's own name
/// and amounts about 124px on a phone, so all three truncated.
class _GoalTimelinePanel extends StatelessWidget {
  final bool wide;
  final String timeInfo;
  final double monthlySavings;
  final double expectedAmount;
  final double currentAmount;

  const _GoalTimelinePanel({
    required this.wide,
    required this.timeInfo,
    required this.monthlySavings,
    required this.expectedAmount,
    required this.currentAmount,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final behind = expectedAmount > 0 && currentAmount < expectedAmount;
    final align = wide ? CrossAxisAlignment.end : CrossAxisAlignment.start;

    final status = expectedAmount <= 0
        ? null
        : _StatusPill(
            behind: behind,
            label: behind
                ? 'Behind by ${CurrencyFormatter.format(expectedAmount - currentAmount)}'
                : 'On track',
          );

    final details = <Widget>[
      Text(timeInfo, style: AppText.caption.copyWith(color: context.muted)),
      if (monthlySavings > 0) ...[
        kGapXs,
        Text(
          'Save ${CurrencyFormatter.format(monthlySavings)} a month',
          style: AppText.amountSmall.copyWith(color: theme.colorScheme.secondary),
        ),
      ],
    ];

    return Container(
      width: wide ? 150 : null,
      margin: wide ? const EdgeInsets.only(left: kSpaceXxl) : null,
      padding: const EdgeInsets.all(kSpaceLg),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.5),
        borderRadius: BorderRadius.circular(8),
      ),
      child: wide
          ? Column(
              crossAxisAlignment: align,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                ...details,
                if (status != null) ...[kGapLg, status],
              ],
            )
          // Side by side when it has the full card width: the recommended
          // saving and the verdict answer the same question.
          : Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: details,
                  ),
                ),
                if (status != null) ...[const SizedBox(width: kSpaceXl), status],
              ],
            ),
    );
  }
}

class _StatusPill extends StatelessWidget {
  final bool behind;
  final String label;

  const _StatusPill({required this.behind, required this.label});

  @override
  Widget build(BuildContext context) {
    final color = behind ? context.negative : context.positive;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withValues(alpha: 0.25)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            behind ? Icons.trending_down : Icons.check_circle_outline,
            color: color,
            size: 13,
          ),
          const SizedBox(width: 5),
          Flexible(
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.fade,
              softWrap: false,
              style: AppText.badge.copyWith(color: color),
            ),
          ),
        ],
      ),
    );
  }
}

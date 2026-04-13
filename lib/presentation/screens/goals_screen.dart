import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:budgett_frontend/presentation/providers/finance_provider.dart';
import 'package:budgett_frontend/presentation/widgets/add_goal_dialog.dart';
import 'package:budgett_frontend/presentation/utils/currency_formatter.dart';
import 'package:budgett_frontend/presentation/widgets/edit_goal_dialog.dart';
import 'package:budgett_frontend/presentation/utils/icon_helper.dart';

class GoalsScreen extends ConsumerWidget {
  const GoalsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final goalsAsync = ref.watch(goalsProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Financial Goals')),
      body: RefreshIndicator(
        onRefresh: () async {
          ref.invalidate(goalsProvider);
          await ref.read(goalsProvider.future);
        },
        child: goalsAsync.when(
        data: (goals) {
          if (goals.isEmpty) {
            return LayoutBuilder(
              builder: (context, constraints) => SingleChildScrollView(
                physics: const AlwaysScrollableScrollPhysics(),
                child: SizedBox(
                  height: constraints.maxHeight,
                  child: const Center(child: Text('No goals set yet. Start dreaming!')),
                ),
              ),
            );
          }
          return ListView.separated(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.all(16),
            itemCount: goals.length,
            separatorBuilder: (context, index) => const SizedBox(height: 12),
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
                elevation: 2,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                child: InkWell(
                  onTap: () {
                    showDialog(
                      context: context,
                      builder: (context) => EditGoalDialog(goal: goal),
                    );
                  },
                  child: Padding(
                    padding: const EdgeInsets.all(16.0),
                    child: Row(
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
                                style: const TextStyle(fontSize: 24),
                              ),
                        ),
                        const SizedBox(width: 16),
                        
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                goal.name,
                                style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                              const SizedBox(height: 4),
                              Row(
                                children: [
                                  Text(
                                    CurrencyFormatter.format(goal.currentAmount, decimalDigits: 0),
                                    style: TextStyle(
                                      color: Theme.of(context).colorScheme.primary,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                  Text(
                                    ' / ${CurrencyFormatter.format(goal.targetAmount, decimalDigits: 0)}',
                                    style: TextStyle(color: Colors.grey[600], fontSize: 13),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 8),
                              Stack(
                                children: [
                                  LinearProgressIndicator(
                                    value: 1, // Full background
                                    backgroundColor: Colors.transparent,
                                    color: Colors.grey.shade200,
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
                                              color: Colors.green.withOpacity(0.3),
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
                                                color: Colors.black.withOpacity(0.35),
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
                        
                        if (deadline != null)
                        Container(
                          width: 150,
                          margin: const EdgeInsets.only(left: 16),
                          padding: const EdgeInsets.all(8),
                          decoration: BoxDecoration(
                            // Removed explicit background color and border as per request "Dont use white background"
                            // Using a subtle surface tone or transparent
                            color: Theme.of(context).colorScheme.surfaceContainerHighest.withOpacity(0.5), 
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.end,
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Text(timeInfo, style: Theme.of(context).textTheme.bodySmall),
                              const SizedBox(height: 4),
                              if (monthlySavings > 0) ...[
                                Text(
                                  'Rec. Savings:',
                                  style: TextStyle(fontSize: 10, color: Colors.grey[600]),
                                ),
                                Text(
                                  CurrencyFormatter.format(monthlySavings, decimalDigits: 0),
                                  style: TextStyle(
                                    color: Theme.of(context).colorScheme.secondary,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                                const SizedBox(height: 4),
                              ],
                              if (expectedAmount > 0 && goal.currentAmount < expectedAmount)
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                                  decoration: BoxDecoration(
                                    color: Colors.red.withOpacity(0.1),
                                    borderRadius: BorderRadius.circular(8),
                                    border: Border.all(color: Colors.red.withOpacity(0.2)),
                                  ),
                                  child: FittedBox(
                                    fit: BoxFit.scaleDown,
                                    alignment: Alignment.centerRight,
                                    child: Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        Icon(Icons.trending_down, color: Colors.red[400], size: 14),
                                        const SizedBox(width: 6),
                                        Text(
                                          'Behind by ${CurrencyFormatter.format(expectedAmount - goal.currentAmount, decimalDigits: 0)}',
                                          style: TextStyle(
                                            fontSize: 10, 
                                            fontWeight: FontWeight.bold,
                                            color: Colors.red[100],
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                )
                              else if (expectedAmount > 0)
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                                  decoration: BoxDecoration(
                                    color: Colors.green.withOpacity(0.1),
                                    borderRadius: BorderRadius.circular(8),
                                    border: Border.all(color: Colors.green.withOpacity(0.2)),
                                  ),
                                  child: FittedBox(
                                    fit: BoxFit.scaleDown,
                                    alignment: Alignment.centerRight,
                                    child: Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        Icon(Icons.check_circle_outline, color: Colors.green[400], size: 14),
                                        const SizedBox(width: 6),
                                        Text(
                                          'On track!',
                                          style: TextStyle(
                                            fontSize: 10, 
                                            fontWeight: FontWeight.bold,
                                            color: Colors.green[100],
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              );
            },
          );
        },
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (err, stack) => Center(child: Text('Error: $err')),
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

import 'package:flutter/material.dart';

import '../../core/responsive.dart';
import '../widgets/screen_title.dart';
import 'budget_screen.dart';
import 'expense_groups_screen.dart';
import 'goals_screen.dart';
import 'recurring_transactions_screen.dart';

/// Everything that answers "what do I intend to do with my money?".
///
/// Budget, goals, recurring charges and expense groups were four separate
/// destinations, three of them behind "More" — which held seven of the app's
/// eleven destinations, a list flat enough that a *task* (reviewing captured
/// expenses) sat next to *settings*. They are one section now, because they
/// are one question asked four ways: the month's plan, the long-term plan,
/// the plan that repeats, and the plan for a trip.
///
/// On desktop this is just the budget: the sidebar already lists all four, so
/// wrapping them in tabs would be a second navigation for the same thing.
class PlanScreen extends StatelessWidget {
  const PlanScreen({super.key});

  @override
  Widget build(BuildContext context) {
    if (context.formFactor == FormFactor.desktop) {
      return const BudgetScreen();
    }

    return DefaultTabController(
      length: 4,
      child: Scaffold(
        appBar: AppBar(
          title: ScreenTitle('Plan'),
          bottom: const TabBar(
            isScrollable: true,
            tabAlignment: TabAlignment.start,
            tabs: [
              Tab(text: 'Budget'),
              Tab(text: 'Goals'),
              Tab(text: 'Recurring'),
              Tab(text: 'Groups'),
            ],
          ),
        ),
        body: const TabBarView(
          children: [
            BudgetScreen(embedded: true),
            GoalsScreen(embedded: true),
            RecurringTransactionsScreen(embedded: true),
            ExpenseGroupsScreen(embedded: true),
          ],
        ),
      ),
    );
  }
}

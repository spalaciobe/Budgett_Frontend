# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Commands

From this directory:

- Install deps: `flutter pub get`
- Run app: `flutter run -d chrome` (web), `flutter run -d windows`, or `flutter run` (mobile). List targets with `flutter devices`.
- Regenerate Riverpod code: `dart run build_runner build --delete-conflicting-outputs`
- Analyze / lint: `flutter analyze`
- Run all tests: `flutter test`
- Run a single test file: `flutter test test/finance_provider_test.dart`
- Run a single test by name: `flutter test --plain-name "<test name>"`

## Supabase connection

`lib/core/app_constants.dart` holds the Supabase URL and anon key — currently points to the **production** instance. To develop against a local Supabase stack, update those two constants to `http://127.0.0.1:54321` and the local anon key.

## Architecture

### Layers (`lib/`)

- **`core/`** – Constants, theme, responsive helpers, platform services (`notification_service.dart`), and domain utilities (`colombian_calendar.dart`, `credit_card_calculator.dart`).
- **`data/`** – Plain Dart models (`models/`) mirroring Supabase tables; repositories (`repositories/`) are the *only* layer that calls Supabase. UI and providers never import `supabase_flutter` directly except for auth/session checks.
- **`presentation/`** – Riverpod providers (`providers/`), `go_router` navigation (`navigation/`), screens, and widgets.

### Responsive layout

`core/responsive.dart` defines `FormFactor` (mobile/tablet/desktop) via a `BuildContext.formFactor` extension. Breakpoints: desktop ≥ 1024 px, tablet ≥ 600 px, mobile otherwise. `MainScaffold` dispatches to three shells: `_DesktopShell` (collapsible sidebar), `_TabletShell` (NavigationRail), `_MobileShell` (bottom NavigationBar). Always test layout changes at all three breakpoints.

### Routing (`app_router.dart`)

Single `GoRouter` with a global redirect: unauthenticated → `/login`; authenticated on `/login` → `/`. There is **no onboarding route** — the router goes directly from login to the main shell. All app screens sit inside a `ShellRoute` wrapping `MainScaffold`; add new routes there. Auth screens go outside it.

### State management

- `financeRepositoryProvider` is the single `FinanceRepository` instance — never instantiate repositories inside widgets or other providers.
- List data: plain `FutureProvider` — `accountsProvider`, `categoriesProvider`, `goalsProvider`, `recentTransactionsProvider`, `recurringTransactionsProvider`, `expenseGroupsProvider`.
- Time-scoped data: `FutureProvider.family` keyed by `({int month, int year})` — `budgetsProvider`.
- Yearly data: `FutureProvider.family<..., int>` keyed by year — `yearlySummaryProvider`.
- `billingCalendarProvider` uses `.autoDispose` (unlike all others).
- **Logout**: always use `performLogout` from `providers/logout_action.dart` — it invalidates all finance providers before calling `signOut()`. Never call `signOut()` directly from UI code.

### FinanceRepository notes

- JWT retry (PGRST303 / "JWT issued at future"): only `getAccounts`, `getRecentTransactions`, and `getYearlySummary` implement the one-retry loop. Add the same pattern to new read methods that will be called immediately after login.
- All write methods stamp `user_id` from `_client.auth.currentUser!.id`; reads filter by it (matching RLS policies on every table).
- Budget and spending aggregations (`getMonthlyIncome`, `getSpendingByCategory`, `getTotalBudgeted`) filter `currency = 'COP'` — USD amounts are intentionally excluded from budget comparisons.

### Domain model field values

| Field | Values |
|---|---|
| `Transaction.type` | `income`, `expense`, `transfer` |
| `Transaction.status` | `pending`, `cleared`, `paid` |
| `Transaction.movementType` | `fixed`, `variable`, `savings`, `income`, `transfer` |
| `Transaction.currency` | `COP`, `USD` |
| `Account.type` | `ahorro`, `corriente`, `tarjeta de crédito`, `efectivo` |

### Credit card logic

`core/utils/credit_card_calculator.dart` is the single source of truth for cutoff dates, payment dates, and billing-period assignment. It consumes `CreditCardRules` (per-account, from `credit_card_details`) and `Bank` (from `bancos` catalog). Colombian business-day logic is in `core/utils/colombian_calendar.dart`. Do not replicate this math in UI code or providers.

DB triggers (not Dart code) maintain account balances — check `Budgett_Backend/supabase/migrations/` before writing any Dart that would recompute balances.

## UI language

All user-facing strings in `.dart` files **must be written in English** — labels, button text, dialog titles, snackbar messages, tooltips, placeholder/hint text, empty-state messages, section headers, and any other copy that appears in the UI.

Do **not** use Spanish for any of the above, even for minor strings like "Cancelar", "Guardar", "Sí", "No", etc. The correct equivalents are "Cancel", "Save", "Yes", "No".

The only exceptions are:
- Internal Map keys used purely for date/calendar calculations (e.g. Colombian holiday names in `colombian_calendar.dart`) — these are never displayed to the user.
- Supabase column name keys in repository/model code (e.g. `banco_id`, `tipo_corte`, `fecha_corte_calculada`) — these must match the DB schema exactly.

## Testing

`test/seed_database.dart` is a helper, not a test suite — do not include it in `flutter test` runs. Relevant test groups:
- Core data layer: `finance_repository_test.dart`, `finance_provider_test.dart`
- Credit card engine: `cc_payment_alerts_test.dart`, `credit_card_rules_ui_test.dart`
- Formatting / seed data: `currency_formatter_test.dart`, `colombian_categories_test.dart`

import 'package:supabase/supabase.dart';

const supabaseUrl = 'http://127.0.0.1:54321';
const supabaseServiceRoleKey = 'sb_secret_N7UND0UgjKTVK-Uodkm0Hg_xSvEMPvz';

void main() async {
  print('🌱 Seeding database...');

  final client = SupabaseClient(supabaseUrl, supabaseServiceRoleKey);

  // 1. Get the first user
  final usersResponse = await client.auth.admin.listUsers();
  
  if (usersResponse.isEmpty) {
    print('❌ No users found in auth.users. Please sign up in the app first!');
    return;
  }

  final userId = usersResponse.first.id;
  print('Found user: $userId. Seeding data for them...');

  // 2. Seed Categories
  final s = client.from('categories');
  final existingCategories = await s.select().eq('user_id', userId);
  
  if ((existingCategories as List).isEmpty) {
    await s.insert([
      {'user_id': userId, 'name': 'Groceries', 'type': 'expense', 'icon': 'shopping_cart'},
      {'user_id': userId, 'name': 'Rent', 'type': 'expense', 'icon': 'home'},
      {'user_id': userId, 'name': 'Salary', 'type': 'income', 'icon': 'work'},
      {'user_id': userId, 'name': 'Transport', 'type': 'expense', 'icon': 'directions_car'},
      {'user_id': userId, 'name': 'Entertainment', 'type': 'expense', 'icon': 'movie'},
    ]);
    print('✅ Categories inserted');
  } else {
    print('ℹ️ Categories already exist');
  }

  // 3. Seed Accounts
  final a = client.from('accounts');
  final existingAccounts = await a.select().eq('user_id', userId);
  List<String> accountIds = [];

  if ((existingAccounts as List).isEmpty) {
    final res = await a.insert([
      {
        'user_id': userId, 
        'name': 'Main Bank', 
        'type': 'checking', 
        'balance': 2500.00
      },
      {
        'user_id': userId, 
        'name': 'Wallet Cash', 
        'type': 'cash', 
        'balance': 150.00
      },
      {
        'user_id': userId, 
        'name': 'Credit Card', 
        'type': 'credit_card', 
        'balance': -450.00,
        'credit_limit': 1000.00,
        'closing_day': 5,
        'payment_due_day': 20
      },
    ]).select();
    
    accountIds = (res as List).map((e) => e['id'] as String).toList();
    print('✅ Accounts inserted');
  } else {
    print('ℹ️ Accounts already exist');
    accountIds = existingAccounts.map((e) => e['id'] as String).toList();
  }

  // 4. Seed Transactions (if we have accounts)
  if (accountIds.isNotEmpty) {
    final t = client.from('transactions');
    final existingTransactions = await t.select().eq('user_id', userId).limit(1);
    
    if ((existingTransactions as List).isEmpty) {
      final mainBankId = accountIds[0];
      // final cashId = accountIds[1]; 
      
      await t.insert([
        {
          'user_id': userId,
          'account_id': mainBankId,
          'amount': 3000.00,
          'description': 'Monthly Salary',
          'date': DateTime.now().subtract(const Duration(days: 2)).toIso8601String(),
          'type': 'income',
        },
        {
          'user_id': userId,
          'account_id': mainBankId,
          'amount': 150.00,
          'description': 'Grocery Store',
          'date': DateTime.now().subtract(const Duration(days: 1)).toIso8601String(),
          'type': 'expense',
        },
        {
          'user_id': userId,
          'account_id': mainBankId,
          'amount': 15.50,
          'description': 'Coffee Shop',
          'date': DateTime.now().toIso8601String(),
          'type': 'expense',
        },
      ]);
      print('✅ Transactions inserted');
    } else {
      print('ℹ️ Transactions already exist');
    }
  }

  print('🎉 database seeding complete!');
}

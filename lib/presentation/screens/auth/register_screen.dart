import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

// ─── Country data ─────────────────────────────────────────────────────────────

class _Country {
  final String name;
  final String iso;
  final String dialCode;

  const _Country(this.name, this.iso, this.dialCode);

  String get flag {
    return iso.toUpperCase().split('').map(
      (c) => String.fromCharCode(c.codeUnitAt(0) - 0x41 + 0x1F1E6),
    ).join();
  }

  String get display => '${flag}  $dialCode';
}

const _kCountries = [
  _Country('Afghanistan', 'AF', '+93'),
  _Country('Albania', 'AL', '+355'),
  _Country('Algeria', 'DZ', '+213'),
  _Country('Argentina', 'AR', '+54'),
  _Country('Australia', 'AU', '+61'),
  _Country('Austria', 'AT', '+43'),
  _Country('Belgium', 'BE', '+32'),
  _Country('Bolivia', 'BO', '+591'),
  _Country('Brazil', 'BR', '+55'),
  _Country('Canada', 'CA', '+1'),
  _Country('Chile', 'CL', '+56'),
  _Country('China', 'CN', '+86'),
  _Country('Colombia', 'CO', '+57'),
  _Country('Costa Rica', 'CR', '+506'),
  _Country('Cuba', 'CU', '+53'),
  _Country('Czech Republic', 'CZ', '+420'),
  _Country('Denmark', 'DK', '+45'),
  _Country('Dominican Republic', 'DO', '+1-809'),
  _Country('Ecuador', 'EC', '+593'),
  _Country('Egypt', 'EG', '+20'),
  _Country('El Salvador', 'SV', '+503'),
  _Country('Finland', 'FI', '+358'),
  _Country('France', 'FR', '+33'),
  _Country('Germany', 'DE', '+49'),
  _Country('Ghana', 'GH', '+233'),
  _Country('Greece', 'GR', '+30'),
  _Country('Guatemala', 'GT', '+502'),
  _Country('Honduras', 'HN', '+504'),
  _Country('Hungary', 'HU', '+36'),
  _Country('India', 'IN', '+91'),
  _Country('Indonesia', 'ID', '+62'),
  _Country('Iran', 'IR', '+98'),
  _Country('Ireland', 'IE', '+353'),
  _Country('Israel', 'IL', '+972'),
  _Country('Italy', 'IT', '+39'),
  _Country('Jamaica', 'JM', '+1-876'),
  _Country('Japan', 'JP', '+81'),
  _Country('Jordan', 'JO', '+962'),
  _Country('Kenya', 'KE', '+254'),
  _Country('Malaysia', 'MY', '+60'),
  _Country('Mexico', 'MX', '+52'),
  _Country('Morocco', 'MA', '+212'),
  _Country('Netherlands', 'NL', '+31'),
  _Country('New Zealand', 'NZ', '+64'),
  _Country('Nicaragua', 'NI', '+505'),
  _Country('Nigeria', 'NG', '+234'),
  _Country('Norway', 'NO', '+47'),
  _Country('Pakistan', 'PK', '+92'),
  _Country('Panama', 'PA', '+507'),
  _Country('Paraguay', 'PY', '+595'),
  _Country('Peru', 'PE', '+51'),
  _Country('Philippines', 'PH', '+63'),
  _Country('Poland', 'PL', '+48'),
  _Country('Portugal', 'PT', '+351'),
  _Country('Puerto Rico', 'PR', '+1-787'),
  _Country('Romania', 'RO', '+40'),
  _Country('Russia', 'RU', '+7'),
  _Country('Saudi Arabia', 'SA', '+966'),
  _Country('South Africa', 'ZA', '+27'),
  _Country('South Korea', 'KR', '+82'),
  _Country('Spain', 'ES', '+34'),
  _Country('Sweden', 'SE', '+46'),
  _Country('Switzerland', 'CH', '+41'),
  _Country('Thailand', 'TH', '+66'),
  _Country('Turkey', 'TR', '+90'),
  _Country('Ukraine', 'UA', '+380'),
  _Country('United Arab Emirates', 'AE', '+971'),
  _Country('United Kingdom', 'GB', '+44'),
  _Country('United States', 'US', '+1'),
  _Country('Uruguay', 'UY', '+598'),
  _Country('Venezuela', 'VE', '+58'),
  _Country('Vietnam', 'VN', '+84'),
];

// ─── Register screen ──────────────────────────────────────────────────────────

class RegisterScreen extends StatefulWidget {
  const RegisterScreen({super.key});

  @override
  State<RegisterScreen> createState() => _RegisterScreenState();
}

class _RegisterScreenState extends State<RegisterScreen> {
  final _formKey = GlobalKey<FormState>();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final _confirmPasswordController = TextEditingController();
  final _usernameController = TextEditingController();
  final _firstNameController = TextEditingController();
  final _lastNameController = TextEditingController();
  final _phoneController = TextEditingController();

  _Country _selectedCountry = _kCountries.firstWhere((c) => c.iso == 'CO');
  bool _isLoading = false;
  bool _obscurePassword = true;
  bool _obscureConfirm = true;

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    _confirmPasswordController.dispose();
    _usernameController.dispose();
    _firstNameController.dispose();
    _lastNameController.dispose();
    _phoneController.dispose();
    super.dispose();
  }

  Future<void> _register() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _isLoading = true);
    try {
      final response = await Supabase.instance.client.auth.signUp(
        email: _emailController.text.trim(),
        password: _passwordController.text,
      );

      final userId = response.user?.id;
      if (userId == null) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Check your email to confirm your account')),
          );
          context.go('/login');
        }
        return;
      }

      // Session available — save profile immediately
      final phone = _phoneController.text.trim();
      final firstName = _firstNameController.text.trim();
      final lastName = _lastNameController.text.trim();
      final username = _usernameController.text.trim();

      await Supabase.instance.client.from('profiles').upsert({
        'id': userId,
        if (username.isNotEmpty) 'username': username,
        if (firstName.isNotEmpty) 'first_name': firstName,
        if (lastName.isNotEmpty) 'last_name': lastName,
        if (phone.isNotEmpty) 'phone': '${_selectedCountry.dialCode} $phone',
      });

      if (mounted) context.go('/');
    } on AuthException catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message)));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Unexpected error occurred')),
        );
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  void _pickCountry() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (context) => _CountryPickerSheet(
        selected: _selectedCountry,
        onSelected: (country) {
          setState(() => _selectedCountry = country);
          Navigator.pop(context);
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Create account')),
      body: Center(
        child: Container(
          constraints: const BoxConstraints(maxWidth: 440),
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: Form(
              key: _formKey,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // ── Account credentials ────────────────────────────────────
                  _SectionLabel('Account'),
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: _emailController,
                    decoration: const InputDecoration(
                      labelText: 'Email',
                      border: OutlineInputBorder(),
                      prefixIcon: Icon(Icons.email_outlined),
                    ),
                    keyboardType: TextInputType.emailAddress,
                    autofillHints: const [AutofillHints.email],
                    validator: (v) {
                      if (v == null || v.trim().isEmpty) return 'Email is required';
                      if (!v.contains('@')) return 'Enter a valid email';
                      return null;
                    },
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: _passwordController,
                    decoration: InputDecoration(
                      labelText: 'Password',
                      border: const OutlineInputBorder(),
                      prefixIcon: const Icon(Icons.lock_outline),
                      suffixIcon: IconButton(
                        icon: Icon(_obscurePassword ? Icons.visibility_outlined : Icons.visibility_off_outlined),
                        onPressed: () => setState(() => _obscurePassword = !_obscurePassword),
                      ),
                    ),
                    obscureText: _obscurePassword,
                    validator: (v) {
                      if (v == null || v.isEmpty) return 'Password is required';
                      if (v.length < 6) return 'At least 6 characters';
                      return null;
                    },
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: _confirmPasswordController,
                    decoration: InputDecoration(
                      labelText: 'Confirm password',
                      border: const OutlineInputBorder(),
                      prefixIcon: const Icon(Icons.lock_outline),
                      suffixIcon: IconButton(
                        icon: Icon(_obscureConfirm ? Icons.visibility_outlined : Icons.visibility_off_outlined),
                        onPressed: () => setState(() => _obscureConfirm = !_obscureConfirm),
                      ),
                    ),
                    obscureText: _obscureConfirm,
                    validator: (v) {
                      if (v != _passwordController.text) return 'Passwords do not match';
                      return null;
                    },
                  ),

                  // ── Profile ────────────────────────────────────────────────
                  const SizedBox(height: 24),
                  _SectionLabel('Profile'),
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: _firstNameController,
                    decoration: const InputDecoration(
                      labelText: 'First name',
                      border: OutlineInputBorder(),
                      prefixIcon: Icon(Icons.person_outline),
                    ),
                    textCapitalization: TextCapitalization.words,
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: _lastNameController,
                    decoration: const InputDecoration(
                      labelText: 'Last name',
                      border: OutlineInputBorder(),
                      prefixIcon: Icon(Icons.person_outline),
                    ),
                    textCapitalization: TextCapitalization.words,
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: _usernameController,
                    decoration: const InputDecoration(
                      labelText: 'Username',
                      border: OutlineInputBorder(),
                      prefixIcon: Icon(Icons.alternate_email),
                    ),
                  ),
                  const SizedBox(height: 12),

                  // ── Phone with country code ────────────────────────────────
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Country code button
                      IntrinsicHeight(
                        child: OutlinedButton(
                          style: OutlinedButton.styleFrom(
                            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 16),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(4),
                            ),
                            side: BorderSide(
                              color: Theme.of(context).colorScheme.outline,
                            ),
                          ),
                          onPressed: _pickCountry,
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(
                                _selectedCountry.flag,
                                style: const TextStyle(fontSize: 20),
                              ),
                              const SizedBox(width: 6),
                              Text(
                                _selectedCountry.dialCode,
                                style: Theme.of(context).textTheme.bodyMedium,
                              ),
                              const SizedBox(width: 4),
                              const Icon(Icons.arrow_drop_down, size: 18),
                            ],
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      // Phone number field
                      Expanded(
                        child: TextFormField(
                          controller: _phoneController,
                          decoration: const InputDecoration(
                            labelText: 'Phone number',
                            border: OutlineInputBorder(),
                          ),
                          keyboardType: TextInputType.phone,
                        ),
                      ),
                    ],
                  ),

                  const SizedBox(height: 32),
                  if (_isLoading)
                    const Center(child: CircularProgressIndicator())
                  else
                    FilledButton(
                      onPressed: _register,
                      child: const Text('Create account'),
                    ),
                  const SizedBox(height: 8),
                  TextButton(
                    onPressed: () => context.go('/login'),
                    child: const Text('Already have an account? Log in'),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

// ─── Section label ────────────────────────────────────────────────────────────

class _SectionLabel extends StatelessWidget {
  final String text;
  const _SectionLabel(this.text);

  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      style: Theme.of(context).textTheme.titleSmall?.copyWith(
            color: Theme.of(context).colorScheme.primary,
            fontWeight: FontWeight.bold,
          ),
    );
  }
}

// ─── Country picker bottom sheet ──────────────────────────────────────────────

class _CountryPickerSheet extends StatefulWidget {
  final _Country selected;
  final ValueChanged<_Country> onSelected;

  const _CountryPickerSheet({
    required this.selected,
    required this.onSelected,
  });

  @override
  State<_CountryPickerSheet> createState() => _CountryPickerSheetState();
}

class _CountryPickerSheetState extends State<_CountryPickerSheet> {
  String _query = '';

  List<_Country> get _filtered {
    if (_query.isEmpty) return _kCountries;
    final q = _query.toLowerCase();
    return _kCountries
        .where((c) => c.name.toLowerCase().contains(q) || c.dialCode.contains(q))
        .toList();
  }

  @override
  Widget build(BuildContext context) {
    final filtered = _filtered;
    return DraggableScrollableSheet(
      initialChildSize: 0.6,
      minChildSize: 0.4,
      maxChildSize: 0.9,
      expand: false,
      builder: (context, scrollController) {
        return Column(
          children: [
            const SizedBox(height: 12),
            Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.outlineVariant,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
              child: TextField(
                autofocus: true,
                decoration: const InputDecoration(
                  hintText: 'Search country',
                  prefixIcon: Icon(Icons.search),
                  border: OutlineInputBorder(),
                  isDense: true,
                ),
                onChanged: (v) => setState(() => _query = v),
              ),
            ),
            Expanded(
              child: ListView.builder(
                controller: scrollController,
                itemCount: filtered.length,
                itemBuilder: (context, i) {
                  final country = filtered[i];
                  return ListTile(
                    leading: Text(
                      country.flag,
                      style: const TextStyle(fontSize: 24),
                    ),
                    title: Text(country.name),
                    trailing: Text(
                      country.dialCode,
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                            color: Theme.of(context).colorScheme.primary,
                            fontWeight: FontWeight.w600,
                          ),
                    ),
                    selected: country.iso == widget.selected.iso,
                    onTap: () => widget.onSelected(country),
                  );
                },
              ),
            ),
          ],
        );
      },
    );
  }
}

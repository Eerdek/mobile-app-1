import 'package:flutter/material.dart';

import '../../core/api_client.dart';
import '../../core/session.dart';
import '../../core/ui.dart';

class LoginScreen extends StatefulWidget {
  final ApiClient api;
  final Session session;
  const LoginScreen({super.key, required this.api, required this.session});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _identity = TextEditingController();
  final _password = TextEditingController();
  bool _hidden = true;
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _identity.dispose();
    _password.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final identity = _identity.text.trim();
    final password = _password.text;
    if (identity.isEmpty || password.isEmpty) {
      setState(() => _error = 'Имэйл эсвэл утас, нууц үгээ бүрэн оруулна уу.');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final (token, user) = await widget.api.login(identity, password);
      await widget.session.save(token, user);
    } on ApiException catch (e) {
      setState(() {
        _error = switch (e.status) {
          401 => 'Имэйл, утас эсвэл нууц үг буруу байна.',
          403 => 'Таны бүртгэл идэвхгүй байна. Системийн админтай холбогдоно уу.',
          final s? when s >= 500 => 'Системтэй холбогдоход алдаа гарлаа. Түр хүлээгээд дахин оролдоно уу.',
          _ => e.message,
        };
      });
    } catch (_) {
      setState(() => _error = 'Нэвтрэх үед алдаа гарлаа.');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(20),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 400),
              child: Card(
                child: Padding(
                  padding: const EdgeInsets.all(20),
                  child: AutofillGroup(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Center(
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(14),
                            child: Image.asset(
                              'assets/images/akifoods-logo.png',
                              // ⚠ contain — лого хэвтээ тул cover нь «KI FOOD» болгож тайрдаг байв.
                              width: 120,
                              height: 84,
                              fit: BoxFit.contain,
                            ),
                          ),
                        ),
                        const SizedBox(height: 14),
                        Text(
                          'AKI Foods',
                          textAlign: TextAlign.center,
                          style: Theme.of(context).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w800),
                        ),
                        const Text(
                          'Ажилтны систем',
                          textAlign: TextAlign.center,
                          style: TextStyle(color: AppColors.muted),
                        ),
                        const SizedBox(height: 22),
                        TextField(
                          controller: _identity,
                          keyboardType: TextInputType.emailAddress,
                          autofillHints: const [AutofillHints.username],
                          textInputAction: TextInputAction.next,
                          decoration: const InputDecoration(labelText: 'Имэйл эсвэл утас'),
                        ),
                        const SizedBox(height: 12),
                        TextField(
                          controller: _password,
                          obscureText: _hidden,
                          autofillHints: const [AutofillHints.password],
                          onSubmitted: (_) => _submit(),
                          decoration: InputDecoration(
                            labelText: 'Нууц үг',
                            suffixIcon: IconButton(
                              tooltip: _hidden ? 'Нууц үг харах' : 'Нууц үг нуух',
                              icon: Icon(_hidden ? Icons.visibility_outlined : Icons.visibility_off_outlined),
                              onPressed: () => setState(() => _hidden = !_hidden),
                            ),
                          ),
                        ),
                        const SizedBox(height: 14),
                        if (_error != null) MessageBanner(AppMessage.error(_error!)),
                        FilledButton(
                          onPressed: _busy ? null : _submit,
                          style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(48)),
                          child: Text(_busy ? 'Нэвтэрч байна...' : 'Нэвтрэх'),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

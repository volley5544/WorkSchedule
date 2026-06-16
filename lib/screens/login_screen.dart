import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../l10n/app_text.dart';
import '../services/auth_service.dart';
import '../widgets/settings_dialog.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key, required this.auth, this.onContinueAsGuest});

  final AuthService auth;

  /// Lets visitors browse the schedule view-only without an account.
  final VoidCallback? onContinueAsGuest;

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  bool _busy = false;
  String? _error;

  Future<void> _signIn() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await widget.auth.signInWithGoogle();
    } on FirebaseAuthException catch (e) {
      if (mounted) {
        setState(() => _error = e.message ?? AppText.of(context).signInFailed);
      }
    } catch (e) {
      if (mounted) setState(() => _error = 'Sign-in failed: $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final t = AppText.of(context);
    return Scaffold(
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        actions: [
          IconButton(
            tooltip: t.settingsTitle,
            icon: const Icon(Icons.settings_outlined),
            onPressed: () => showSettingsDialog(context),
          ),
          const SizedBox(width: 4),
        ],
      ),
      extendBodyBehindAppBar: true,
      body: Center(
        child: Card(
          margin: const EdgeInsets.all(24),
          child: Container(
            width: 400,
            padding: const EdgeInsets.all(32),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.local_pharmacy, size: 64, color: scheme.primary),
                const SizedBox(height: 16),
                Text(
                  t.appTitle,
                  textAlign: TextAlign.center,
                  style: Theme.of(context)
                      .textTheme
                      .headlineSmall
                      ?.copyWith(fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 8),
                Text(
                  t.loginSubtitle,
                  textAlign: TextAlign.center,
                  style: Theme.of(context)
                      .textTheme
                      .bodyMedium
                      ?.copyWith(color: scheme.onSurfaceVariant),
                ),
                const SizedBox(height: 28),
                FilledButton.icon(
                  onPressed: _busy ? null : _signIn,
                  icon: _busy
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.login),
                  label: Text(_busy ? t.signingIn : t.signInWithGoogle),
                  style: FilledButton.styleFrom(
                    minimumSize: const Size.fromHeight(48),
                  ),
                ),
                if (widget.onContinueAsGuest != null) ...[
                  const SizedBox(height: 12),
                  OutlinedButton.icon(
                    onPressed: _busy ? null : widget.onContinueAsGuest,
                    icon: const Icon(Icons.visibility_outlined),
                    label: Text(t.continueWithoutSignIn),
                    style: OutlinedButton.styleFrom(
                      minimumSize: const Size.fromHeight(48),
                    ),
                  ),
                ],
                if (_error != null) ...[
                  const SizedBox(height: 16),
                  Text(
                    _error!,
                    textAlign: TextAlign.center,
                    style: TextStyle(color: scheme.error),
                  ),
                ],
                const SizedBox(height: 16),
                Text(
                  t.newAccountNote,
                  textAlign: TextAlign.center,
                  style: Theme.of(context)
                      .textTheme
                      .bodySmall
                      ?.copyWith(color: scheme.onSurfaceVariant),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

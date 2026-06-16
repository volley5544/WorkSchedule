import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:intl/intl.dart';

import 'firebase_options.dart';
import 'l10n/app_text.dart';
import 'models/app_user.dart';
import 'screens/home_screen.dart';
import 'screens/login_screen.dart';
import 'services/app_settings.dart';
import 'services/auth_service.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // Load locale date symbols so DateFormat works for Thai (and any locale),
  // not just the default en_US — otherwise formatting throws on first render.
  await initializeDateFormatting();
  await AppSettings.instance.load();
  String? setupError;
  try {
    await Firebase.initializeApp(
      options: DefaultFirebaseOptions.currentPlatform,
    );
  } catch (e) {
    setupError = e.toString();
  }
  runApp(WorkScheduleApp(setupError: setupError));
}

class WorkScheduleApp extends StatelessWidget {
  const WorkScheduleApp({super.key, this.setupError});

  final String? setupError;

  @override
  Widget build(BuildContext context) {
    final settings = AppSettings.instance;
    return ListenableBuilder(
      listenable: settings,
      builder: (context, _) {
        // Keep intl's default locale in sync so DateFormat output matches the
        // chosen language.
        Intl.defaultLocale = settings.locale.languageCode;
        return MaterialApp(
          title: 'Pharmacy Work Schedule',
          debugShowCheckedModeBanner: false,
          locale: settings.locale,
          supportedLocales: AppSettings.supportedLocales,
          localizationsDelegates: const [
            GlobalMaterialLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
          ],
          themeMode: settings.themeMode,
          theme: ThemeData(
            useMaterial3: true,
            colorScheme:
                ColorScheme.fromSeed(seedColor: const Color(0xFF00897B)),
          ),
          darkTheme: ThemeData(
            useMaterial3: true,
            colorScheme: ColorScheme.fromSeed(
              seedColor: const Color(0xFF00897B),
              brightness: Brightness.dark,
            ),
          ),
          home: setupError != null
              ? _SetupErrorScreen(error: setupError!)
              : const _AuthGate(),
        );
      },
    );
  }
}

/// Routes between login and home based on Firebase auth state, then waits for
/// the Firestore profile (which carries the role) before showing the schedule.
class _AuthGate extends StatefulWidget {
  const _AuthGate();

  @override
  State<_AuthGate> createState() => _AuthGateState();
}

class _AuthGateState extends State<_AuthGate> {
  final _auth = AuthService();

  /// Browsing without an account (view-only By day / Roster).
  bool _guest = false;

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<User?>(
      stream: _auth.authStateChanges,
      builder: (context, authSnap) {
        if (authSnap.connectionState == ConnectionState.waiting) {
          return const _LoadingScreen();
        }
        final user = authSnap.data;
        if (user == null) {
          if (_guest) {
            return HomeScreen(
              user: AppUser.guest,
              auth: _auth,
              onSignIn: () => setState(() => _guest = false),
            );
          }
          return LoginScreen(
            auth: _auth,
            onContinueAsGuest: () => setState(() => _guest = true),
          );
        }
        return StreamBuilder<AppUser?>(
          stream: _auth.userProfile(user.uid),
          builder: (context, profileSnap) {
            if (profileSnap.hasError) {
              return _ProfileErrorScreen(
                error: profileSnap.error.toString(),
                onSignOut: _auth.signOut,
              );
            }
            final profile = profileSnap.data;
            // Profile doc may lag a moment behind first sign-in while
            // _ensureUserDoc creates it.
            if (profile == null) return const _LoadingScreen();
            return HomeScreen(user: profile, auth: _auth);
          },
        );
      },
    );
  }
}

class _LoadingScreen extends StatelessWidget {
  const _LoadingScreen();

  @override
  Widget build(BuildContext context) {
    return const Scaffold(body: Center(child: CircularProgressIndicator()));
  }
}

class _ProfileErrorScreen extends StatelessWidget {
  const _ProfileErrorScreen({required this.error, required this.onSignOut});

  final String error;
  final Future<void> Function() onSignOut;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final t = AppText.of(context);
    return Scaffold(
      body: Center(
        child: Card(
          margin: const EdgeInsets.all(24),
          child: Container(
            width: 560,
            padding: const EdgeInsets.all(32),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(children: [
                  Icon(Icons.error_outline,
                      color: theme.colorScheme.error, size: 32),
                  const SizedBox(width: 12),
                  Text(t.profileErrorTitle,
                      style: theme.textTheme.titleLarge
                          ?.copyWith(fontWeight: FontWeight.bold)),
                ]),
                const SizedBox(height: 16),
                const Text(
                  'Sign-in succeeded, but reading your profile from Cloud '
                  'Firestore failed. This usually means the security rules in '
                  'firestore.rules have not been deployed, or the Firestore '
                  'database has not been created yet.',
                ),
                const SizedBox(height: 16),
                SelectableText('Details: $error',
                    style: theme.textTheme.bodySmall
                        ?.copyWith(color: theme.colorScheme.error)),
                const SizedBox(height: 16),
                OutlinedButton.icon(
                  onPressed: onSignOut,
                  icon: const Icon(Icons.logout),
                  label: Text(t.signOut),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _SetupErrorScreen extends StatelessWidget {
  const _SetupErrorScreen({required this.error});

  final String error;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      body: Center(
        child: Card(
          margin: const EdgeInsets.all(24),
          child: Container(
            width: 560,
            padding: const EdgeInsets.all(32),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(children: [
                  Icon(Icons.build_circle_outlined,
                      color: theme.colorScheme.primary, size: 32),
                  const SizedBox(width: 12),
                  Text('Firebase setup required',
                      style: theme.textTheme.titleLarge
                          ?.copyWith(fontWeight: FontWeight.bold)),
                ]),
                const SizedBox(height: 16),
                const Text('To connect this app to your Firebase project:'),
                const SizedBox(height: 12),
                const SelectableText(
                  '1. Create a project at https://console.firebase.google.com\n'
                  '2. Enable Authentication → Sign-in method → Google\n'
                  '3. Create a Cloud Firestore database\n'
                  '4. From this project folder run:\n\n'
                  '     dart pub global activate flutterfire_cli\n'
                  '     flutterfire configure\n\n'
                  '5. Deploy the security rules in firestore.rules\n'
                  '6. Restart the app',
                  style: TextStyle(fontFamily: 'monospace', height: 1.5),
                ),
                const SizedBox(height: 16),
                Text('Details: $error',
                    style: theme.textTheme.bodySmall
                        ?.copyWith(color: theme.colorScheme.error)),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// PLACEHOLDER — replace by running the FlutterFire CLI from the project root:
//
//   dart pub global activate flutterfire_cli
//   flutterfire configure
//
// That command creates a Firebase project link and OVERWRITES this file with
// your real keys. Until then the app boots into a setup-instructions screen.
import 'package:firebase_core/firebase_core.dart';

class DefaultFirebaseOptions {
  static FirebaseOptions get currentPlatform {
    if (apiKey == 'REPLACE_ME') {
      throw UnsupportedError(
        'Firebase is not configured yet. Run `flutterfire configure` to '
        'generate lib/firebase_options.dart for your Firebase project.',
      );
    }
    return const FirebaseOptions(
      apiKey: apiKey,
      appId: 'REPLACE_ME',
      messagingSenderId: 'REPLACE_ME',
      projectId: 'REPLACE_ME',
    );
  }

  static const apiKey = 'REPLACE_ME';
}

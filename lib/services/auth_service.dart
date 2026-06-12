import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';

import '../models/app_user.dart';

class AuthService {
  final _auth = FirebaseAuth.instance;
  final _db = FirebaseFirestore.instance;

  Stream<User?> get authStateChanges => _auth.authStateChanges();

  /// Signs in with Google. On web this opens a popup; on Android/iOS the
  /// Firebase SDK runs the native OAuth flow, so no extra plugin is needed.
  Future<void> signInWithGoogle() async {
    final provider = GoogleAuthProvider();
    final credential = kIsWeb
        ? await _auth.signInWithPopup(provider)
        : await _auth.signInWithProvider(provider);
    final user = credential.user;
    if (user != null) await _ensureUserDoc(user);
  }

  Future<void> signOut() => _auth.signOut();

  /// Creates the Firestore profile on first sign-in (role defaults to viewer;
  /// security rules prevent self-assigning a higher role). Existing roles are
  /// never touched here.
  Future<void> _ensureUserDoc(User user) async {
    final ref = _db.collection('users').doc(user.uid);
    final snap = await ref.get();
    if (!snap.exists) {
      await ref.set(AppUser(
        uid: user.uid,
        email: user.email ?? '',
        displayName: user.displayName ?? user.email ?? 'Unknown',
        role: UserRole.viewer,
        photoUrl: user.photoURL,
      ).toMap());
    } else {
      await ref.set({
        'email': user.email,
        'displayName': user.displayName ?? user.email,
        'photoUrl': user.photoURL,
      }, SetOptions(merge: true));
    }
  }

  /// Live profile (including role) of the signed-in user.
  Stream<AppUser?> userProfile(String uid) => _db
      .collection('users')
      .doc(uid)
      .snapshots()
      .map((doc) => doc.exists ? AppUser.fromDoc(doc) : null);
}

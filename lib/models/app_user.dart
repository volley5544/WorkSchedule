import 'package:cloud_firestore/cloud_firestore.dart';

/// Access levels for the schedule.
/// - viewer: can only view the schedule (default for new sign-ins)
/// - editor: can create / edit / delete shifts
/// - admin: editor rights + can manage user roles
enum UserRole { viewer, editor, admin }

extension UserRoleX on UserRole {
  String get label => switch (this) {
        UserRole.viewer => 'Viewer',
        UserRole.editor => 'Editor',
        UserRole.admin => 'Admin',
      };

  bool get canEdit => this == UserRole.editor || this == UserRole.admin;
  bool get isAdmin => this == UserRole.admin;

  static UserRole fromString(String? value) => UserRole.values.firstWhere(
        (r) => r.name == value,
        orElse: () => UserRole.viewer,
      );
}

class AppUser {
  const AppUser({
    required this.uid,
    required this.email,
    required this.displayName,
    required this.role,
    this.photoUrl,
  });

  final String uid;
  final String email;
  final String displayName;
  final UserRole role;
  final String? photoUrl;

  /// Stand-in for visitors browsing without an account: view-only, no
  /// profile document. Identified by the empty uid.
  static const guest = AppUser(
    uid: '',
    email: '',
    displayName: 'Guest',
    role: UserRole.viewer,
  );

  bool get isGuest => uid.isEmpty;

  factory AppUser.fromDoc(DocumentSnapshot<Map<String, dynamic>> doc) {
    final data = doc.data() ?? {};
    return AppUser(
      uid: doc.id,
      email: data['email'] as String? ?? '',
      displayName: data['displayName'] as String? ?? '',
      role: UserRoleX.fromString(data['role'] as String?),
      photoUrl: data['photoUrl'] as String?,
    );
  }

  Map<String, dynamic> toMap() => {
        'email': email,
        'displayName': displayName,
        'role': role.name,
        'photoUrl': photoUrl,
      };
}

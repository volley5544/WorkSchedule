import 'package:cloud_firestore/cloud_firestore.dart';

/// A pharmacist on the roster, stored in the `pharmacists` collection and
/// managed by admins. Optionally linked to a signed-in account ([uid]) so
/// that user can use the "My shifts" view.
class Pharmacist {
  const Pharmacist({
    required this.id,
    required this.name,
    this.title = '',
    this.lastname = '',
    this.nickname = '',
    this.queue = 0,
    this.uid,
  });

  final String id;

  /// Name title / คำนำหน้า (e.g. นางสาว, นาย, ภญ.).
  final String title;

  /// First name (e.g. ศรีสกุล).
  final String name;
  final String lastname;
  final String nickname;

  /// Queue number (เลขที่ Que); also the sort order of roster rows.
  final int queue;

  /// Uid of the linked user account, if any.
  final String? uid;

  /// 'title name lastname' ('' parts skipped; no space after the title,
  /// matching Thai convention e.g. นางสาวศรีสกุล สินสวัสดิ์).
  String get fullName {
    final base =
        [name, lastname].where((part) => part.isNotEmpty).join(' ');
    return '$title$base';
  }

  /// Full name with the nickname in parentheses, when set.
  String get displayName =>
      nickname.isEmpty ? fullName : '$fullName ($nickname)';

  factory Pharmacist.fromDoc(DocumentSnapshot<Map<String, dynamic>> doc) {
    final data = doc.data() ?? {};
    return Pharmacist(
      id: doc.id,
      name: data['name'] as String? ?? '',
      title: data['title'] as String? ?? '',
      lastname: data['lastname'] as String? ?? '',
      nickname: data['nickname'] as String? ?? '',
      queue: data['queue'] as int? ?? 0,
      uid: data['uid'] as String?,
    );
  }

  Map<String, dynamic> toMap() => {
        'name': name,
        'title': title,
        'lastname': lastname,
        'nickname': nickname,
        'queue': queue,
        'uid': uid,
      };
}

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
    this.showOrder = 0,
    this.partTime = false,
    this.uid,
  });

  final String id;

  /// Name title / คำนำหน้า (e.g. นางสาว, นาย, ภญ.).
  final String title;

  /// First name (e.g. ศรีสกุล).
  final String name;
  final String lastname;
  final String nickname;

  /// Queue number (เลขที่ Que); the rotation/scheduling order.
  final int queue;

  /// Display order for the Roster/Original tables, independent of [queue]
  /// (e.g. by seniority, "oldest first"). 0 = unset → falls back to [queue].
  final int showOrder;

  /// A part-time pharmacist is left out of the default rotation queue, so
  /// auto-schedule never gives them the regular shifts. They are only assigned
  /// where added explicitly to a shift type's custom rotation.
  final bool partTime;

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

  /// Orders pharmacists for UI display by [showOrder], with 0 ("unset") sorting
  /// after the explicitly-ordered ones, then by [queue]. Used everywhere
  /// pharmacists are listed; the auto-scheduler still rotates by [queue].
  static int byShowOrder(Pharmacist a, Pharmacist b) {
    int rank(Pharmacist p) => p.showOrder == 0 ? 1 << 30 : p.showOrder;
    final byShow = rank(a).compareTo(rank(b));
    return byShow != 0 ? byShow : a.queue.compareTo(b.queue);
  }

  factory Pharmacist.fromDoc(DocumentSnapshot<Map<String, dynamic>> doc) {
    final data = doc.data() ?? {};
    return Pharmacist(
      id: doc.id,
      name: data['name'] as String? ?? '',
      title: data['title'] as String? ?? '',
      lastname: data['lastname'] as String? ?? '',
      nickname: data['nickname'] as String? ?? '',
      queue: data['queue'] as int? ?? 0,
      showOrder: data['showOrder'] as int? ?? 0,
      partTime: data['partTime'] as bool? ?? false,
      uid: data['uid'] as String?,
    );
  }

  Map<String, dynamic> toMap() => {
        'name': name,
        'title': title,
        'lastname': lastname,
        'nickname': nickname,
        'queue': queue,
        'showOrder': showOrder,
        'partTime': partTime,
        'uid': uid,
      };
}

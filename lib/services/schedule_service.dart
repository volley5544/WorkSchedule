import 'package:cloud_firestore/cloud_firestore.dart';

import '../models/app_user.dart';
import '../models/shift.dart';

class ScheduleService {
  final _db = FirebaseFirestore.instance;

  CollectionReference<Map<String, dynamic>> get _shifts =>
      _db.collection('shifts');

  /// All shifts in the month containing [month], keyed by day.
  Stream<Map<String, List<Shift>>> shiftsForMonth(DateTime month) {
    final first = DateTime(month.year, month.month, 1);
    final last = DateTime(month.year, month.month + 1, 0);
    return _shifts
        .where('dateKey', isGreaterThanOrEqualTo: Shift.keyFor(first))
        .where('dateKey', isLessThanOrEqualTo: Shift.keyFor(last))
        .snapshots()
        .map((snap) {
      final byDay = <String, List<Shift>>{};
      for (final doc in snap.docs) {
        final shift = Shift.fromDoc(doc);
        byDay.putIfAbsent(shift.dateKey, () => []).add(shift);
      }
      for (final list in byDay.values) {
        list.sort((a, b) => a.start.compareTo(b.start));
      }
      return byDay;
    });
  }

  Future<void> saveShift(Shift shift) {
    if (shift.id.isEmpty) return _shifts.add(shift.toMap());
    return _shifts.doc(shift.id).set(shift.toMap(), SetOptions(merge: true));
  }

  Future<void> deleteShift(String id) => _shifts.doc(id).delete();

  Stream<List<AppUser>> allUsers() => _db
      .collection('users')
      .orderBy('displayName')
      .snapshots()
      .map((snap) => snap.docs.map(AppUser.fromDoc).toList());

  Future<void> setUserRole(String uid, UserRole role) =>
      _db.collection('users').doc(uid).update({'role': role.name});
}

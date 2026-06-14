import 'package:cloud_firestore/cloud_firestore.dart';

import '../models/app_user.dart';
import '../models/holiday.dart';
import '../models/pharmacist.dart';
import '../models/shift.dart';
import '../models/shift_type.dart';

class ScheduleService {
  final _db = FirebaseFirestore.instance;

  CollectionReference<Map<String, dynamic>> get _shifts =>
      _db.collection('shifts');

  /// Read-only baseline of the roster, captured at auto-schedule time. The
  /// live `shifts` collection diverges from this as pharmacists swap shifts;
  /// keeping the snapshot separate lets the app show "what was originally
  /// generated" next to the current (edited) roster.
  CollectionReference<Map<String, dynamic>> get _originalShifts =>
      _db.collection('originalShifts');

  CollectionReference<Map<String, dynamic>> get _shiftTypes =>
      _db.collection('shiftTypes');

  /// Shift type config, ordered for display. Readable by everyone signed in;
  /// security rules restrict writes to admins.
  Stream<List<ShiftType>> shiftTypes() => _shiftTypes
      .orderBy('sortOrder')
      .snapshots()
      .map((snap) => snap.docs.map(ShiftType.fromDoc).toList());

  Future<void> saveShiftType(ShiftType type) {
    if (type.id.isEmpty) return _shiftTypes.add(type.toMap()).then((_) {});
    return _shiftTypes.doc(type.id).set(type.toMap());
  }

  Future<void> deleteShiftType(String id) => _shiftTypes.doc(id).delete();

  /// Standard Thai name titles, used until an admin saves a custom list.
  static const defaultNameTitles = ['นาย', 'นางสาว', 'นาง', 'คุณ'];

  DocumentReference<Map<String, dynamic>> get _nameTitlesDoc =>
      _db.collection('config').doc('nameTitles');

  /// Configurable list of name titles (คำนำหน้า) for pharmacists.
  Stream<List<String>> nameTitles() => _nameTitlesDoc.snapshots().map((doc) {
    final values = (doc.data()?['values'] as List?)?.cast<String>();
    return (values == null || values.isEmpty) ? defaultNameTitles : values;
  });

  Future<void> saveNameTitles(List<String> titles) =>
      _nameTitlesDoc.set({'values': titles});

  CollectionReference<Map<String, dynamic>> get _pharmacists =>
      _db.collection('pharmacists');

  /// Pharmacist roster config, ordered by queue number. Readable by everyone
  /// signed in; security rules restrict writes to admins.
  Stream<List<Pharmacist>> pharmacists() => _pharmacists
      .orderBy('queue')
      .snapshots()
      .map((snap) => snap.docs.map(Pharmacist.fromDoc).toList());

  Future<void> savePharmacist(Pharmacist pharmacist) {
    if (pharmacist.id.isEmpty) {
      return _pharmacists.add(pharmacist.toMap()).then((_) {});
    }
    return _pharmacists.doc(pharmacist.id).set(pharmacist.toMap());
  }

  Future<void> deletePharmacist(String id) => _pharmacists.doc(id).delete();

  CollectionReference<Map<String, dynamic>> get _holidays =>
      _db.collection('holidays');

  /// Clinic holidays, ordered by date. Readable by everyone (shown on the
  /// public calendar); security rules restrict writes to admins.
  Stream<List<Holiday>> holidays() => _holidays
      .orderBy('dateKey')
      .snapshots()
      .map((snap) => snap.docs.map(Holiday.fromDoc).toList());

  /// One holiday per date: the [Holiday.dateKey] is used as the doc id, so
  /// saving the same date twice just updates it (no duplicates).
  Future<void> saveHoliday(Holiday holiday) =>
      _holidays.doc(holiday.dateKey).set(holiday.toMap());

  Future<void> deleteHoliday(String dateKey) => _holidays.doc(dateKey).delete();

  /// Seeds the posted B.E. 2569 clinic holidays; used when the config is still
  /// empty. Keyed by date, so re-running it is idempotent.
  Future<void> seedHolidays2569() {
    final batch = _db.batch();
    for (final holiday in Holiday.defaults2569) {
      batch.set(_holidays.doc(holiday.dateKey), holiday.toMap());
    }
    return batch.commit();
  }

  /// Seeds the hospital's standard shifts (ช/ย/บ/ด); used when the config
  /// collection is still empty.
  Future<void> seedDefaultShiftTypes() {
    final batch = _db.batch();
    for (final type in ShiftType.defaults) {
      batch.set(_shiftTypes.doc(), type.toMap());
    }
    return batch.commit();
  }

  /// All shifts in the month containing [month], keyed by day.
  Stream<Map<String, List<Shift>>> shiftsForMonth(DateTime month) =>
      _monthShifts(_shifts, month);

  /// The read-only "original" baseline for the month containing [month], keyed
  /// by day — the roster as it was auto-generated, before any shift swaps.
  Stream<Map<String, List<Shift>>> originalShiftsForMonth(DateTime month) =>
      _monthShifts(_originalShifts, month);

  /// Streams the shifts of [col] in the month containing [month], grouped by
  /// day and sorted by start time. Shared by the live and original rosters.
  Stream<Map<String, List<Shift>>> _monthShifts(
    CollectionReference<Map<String, dynamic>> col,
    DateTime month,
  ) {
    final first = DateTime(month.year, month.month, 1);
    final last = DateTime(month.year, month.month + 1, 0);
    return col
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

  /// Auto-fills the roster for [months] months starting at [startMonth].
  ///
  /// Walks every day in the range and, for each shift type active on that
  /// weekday (in sortOrder), assigns the next pharmacist in queue order,
  /// looping 1 → 2 → … → n → 1. The rotation continues from the last
  /// scheduled shift of the month *before* [startMonth] (e.g. if 30 June
  /// ended on pharmacist 5, 1 July starts with pharmacist 6).
  ///
  /// With [replaceExisting] the selected months are wiped first and fully
  /// regenerated; otherwise days that already have a shift of a given type
  /// are left untouched (and don't advance the rotation). Returns the
  /// number of shifts created.
  Future<int> autoSchedule({
    required DateTime startMonth,
    required int months,
    required List<ShiftType> types,
    required List<Pharmacist> pharmacists,
    required String createdBy,
    bool replaceExisting = false,
  }) async {
    if (types.isEmpty || pharmacists.isEmpty || months < 1) return 0;
    final first = DateTime(startMonth.year, startMonth.month, 1);
    final last = DateTime(startMonth.year, startMonth.month + months, 0);

    final sortedTypes = [...types]
      ..sort((a, b) => a.sortOrder.compareTo(b.sortOrder));
    final typeOrder = {
      for (var i = 0; i < sortedTypes.length; i++) sortedTypes[i].id: i,
    };

    // Continue the rotation from the previous month's last scheduled shift.
    var index = 0;
    final prevSnap = await _shifts
        .where(
          'dateKey',
          isGreaterThanOrEqualTo: Shift.keyFor(
            DateTime(first.year, first.month - 1, 1),
          ),
        )
        .where(
          'dateKey',
          isLessThanOrEqualTo: Shift.keyFor(
            DateTime(first.year, first.month, 0),
          ),
        )
        .get();
    final prevShifts =
        prevSnap.docs
            .map(Shift.fromDoc)
            .where((s) => s.pharmacistId.isNotEmpty)
            .toList()
          ..sort((a, b) {
            final byDay = a.dateKey.compareTo(b.dateKey);
            if (byDay != 0) return byDay;
            final byType = (typeOrder[a.typeId] ?? 0).compareTo(
              typeOrder[b.typeId] ?? 0,
            );
            if (byType != 0) return byType;
            return a.start.compareTo(b.start);
          });
    if (prevShifts.isNotEmpty) {
      final lastIndex = pharmacists.indexWhere(
        (p) => p.id == prevShifts.last.pharmacistId,
      );
      if (lastIndex != -1) index = (lastIndex + 1) % pharmacists.length;
    }

    final existingSnap = await _shifts
        .where('dateKey', isGreaterThanOrEqualTo: Shift.keyFor(first))
        .where('dateKey', isLessThanOrEqualTo: Shift.keyFor(last))
        .get();

    var created = 0;
    var batch = _db.batch();
    var ops = 0;
    Future<void> flushIfFull() async {
      if (ops < 450) return; // Firestore caps a batch at 500 writes.
      await batch.commit();
      batch = _db.batch();
      ops = 0;
    }

    // Either wipe the range for a clean regeneration, or note what is
    // already scheduled so it stays as-is.
    final taken = <String>{};
    if (replaceExisting) {
      for (final doc in existingSnap.docs) {
        batch.delete(doc.reference);
        ops++;
        await flushIfFull();
      }
    } else {
      taken.addAll(
        existingSnap.docs
            .map(Shift.fromDoc)
            .map((shift) => '${shift.dateKey}|${shift.typeId}'),
      );
    }

    // Each shift created this run, mirrored into the original baseline below.
    final generated = <Shift>[];
    for (
      var day = first;
      !day.isAfter(last);
      day = DateTime(day.year, day.month, day.day + 1)
    ) {
      final dateKey = Shift.keyFor(day);
      for (final type in sortedTypes) {
        if (!type.days.contains(day.weekday)) continue;
        if (taken.contains('$dateKey|${type.id}')) continue;
        final pharmacist = pharmacists[index];
        index = (index + 1) % pharmacists.length;
        final shift = Shift(
          id: '',
          dateKey: dateKey,
          typeId: type.id,
          start: type.start,
          end: type.end,
          pharmacist: pharmacist.fullName,
          pharmacistId: pharmacist.id,
          createdBy: createdBy,
        );
        batch.set(_shifts.doc(), shift.toMap());
        generated.add(shift);
        created++;
        ops++;
        await flushIfFull();
      }
    }
    if (ops > 0) await batch.commit();

    await _snapshotOriginal(
      first: first,
      last: last,
      generated: generated,
      replaceExisting: replaceExisting,
    );
    return created;
  }

  /// Mirrors freshly generated shifts into the read-only `originalShifts`
  /// baseline, so the app can show the schedule "as auto-generated" before any
  /// pharmacist swaps. One entry per (day × shift type) via a deterministic
  /// doc id. With [replaceExisting] the whole range's baseline is wiped first;
  /// otherwise only the regenerated slots are overwritten and prior baseline
  /// entries are left intact.
  Future<void> _snapshotOriginal({
    required DateTime first,
    required DateTime last,
    required List<Shift> generated,
    required bool replaceExisting,
  }) async {
    var batch = _db.batch();
    var ops = 0;
    Future<void> flushIfFull() async {
      if (ops < 450) return;
      await batch.commit();
      batch = _db.batch();
      ops = 0;
    }

    if (replaceExisting) {
      final old = await _originalShifts
          .where('dateKey', isGreaterThanOrEqualTo: Shift.keyFor(first))
          .where('dateKey', isLessThanOrEqualTo: Shift.keyFor(last))
          .get();
      for (final doc in old.docs) {
        batch.delete(doc.reference);
        ops++;
        await flushIfFull();
      }
    }
    for (final shift in generated) {
      batch.set(
        _originalShifts.doc('${shift.dateKey}_${shift.typeId}'),
        shift.toMap(),
      );
      ops++;
      await flushIfFull();
    }
    if (ops > 0) await batch.commit();
  }

  Stream<List<AppUser>> allUsers() => _db
      .collection('users')
      .orderBy('displayName')
      .snapshots()
      .map((snap) => snap.docs.map(AppUser.fromDoc).toList());

  Future<void> setUserRole(String uid, UserRole role) =>
      _db.collection('users').doc(uid).update({'role': role.name});
}

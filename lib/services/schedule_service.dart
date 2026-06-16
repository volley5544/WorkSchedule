import 'package:cloud_firestore/cloud_firestore.dart';

import '../models/app_user.dart';
import '../models/holiday.dart';
import '../models/pharmacist.dart';
import '../models/shift.dart';
import '../models/shift_type.dart';
import 'schedule_planner.dart';

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

  /// Persists a new ordering of shift types by writing each id's position in
  /// [orderedIds] to its `sortOrder`. This order is what the auto-scheduler
  /// uses to decide which shift type is assigned first each day.
  Future<void> reorderShiftTypes(List<String> orderedIds) {
    final batch = _db.batch();
    for (var i = 0; i < orderedIds.length; i++) {
      batch.update(_shiftTypes.doc(orderedIds[i]), {'sortOrder': i});
    }
    return batch.commit();
  }

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

  /// Persists a new pharmacist order by writing each id's position in
  /// [orderedIds] (1-based) to either `showOrder` (the UI/table display order)
  /// when [byDisplay] is true, or `queue` (the scheduling rotation order)
  /// otherwise.
  Future<void> reorderPharmacists(
    List<String> orderedIds, {
    bool byDisplay = false,
  }) {
    final field = byDisplay ? 'showOrder' : 'queue';
    final batch = _db.batch();
    for (var i = 0; i < orderedIds.length; i++) {
      batch.update(_pharmacists.doc(orderedIds[i]), {field: i + 1});
    }
    return batch.commit();
  }

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
            list.sort(Shift.byStartTime);
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
  /// The scheduling rules live in the pure [planSchedule] planner; this method
  /// only does the Firestore I/O around it: it loads the previous month's
  /// *Original* baseline (to continue each rotation, ignoring swaps), loads
  /// what's already in the live roster range, runs the planner, and writes the
  /// result.
  ///
  /// Each shift type rotates **independently**, with its own counter per day
  /// bucket (weekday / weekend / holiday). [holidayKeys] are the `yyyy-MM-dd`
  /// keys of clinic holidays; a holiday is treated as a non-working day, so
  /// only types flagged [ShiftType.onHoliday] are scheduled then.
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
    Set<String> holidayKeys = const {},
    bool replaceExisting = false,
  }) async {
    if (types.isEmpty || pharmacists.isEmpty || months < 1) return 0;
    final first = DateTime(startMonth.year, startMonth.month, 1);
    final last = DateTime(startMonth.year, startMonth.month + months, 0);

    PlannedShift toPlanned(Shift s) => PlannedShift(
          dateKey: s.dateKey,
          typeId: s.typeId,
          pharmacistId: s.pharmacistId,
          start: s.start,
          end: s.end,
        );

    // The previous month seeds each (type × bucket) rotation counter. This
    // reads the read-only Original baseline (not the live roster), so one-off
    // shift swaps in a previous month don't permanently drift the rotation —
    // continuation follows the clean auto-generated order. Falls back to an
    // empty tail (rotation starts fresh) when that month was never generated.
    final prevSnap = await _originalShifts
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
    final priorTail = prevSnap.docs
        .map(Shift.fromDoc)
        .where((s) => s.pharmacistId.isNotEmpty)
        .map(toPlanned)
        .toList();

    final existingSnap = await _shifts
        .where('dateKey', isGreaterThanOrEqualTo: Shift.keyFor(first))
        .where('dateKey', isLessThanOrEqualTo: Shift.keyFor(last))
        .get();
    final existing = existingSnap.docs.map(Shift.fromDoc).toList();

    var batch = _db.batch();
    var ops = 0;
    Future<void> flushIfFull() async {
      if (ops < 450) return; // Firestore caps a batch at 500 writes.
      await batch.commit();
      batch = _db.batch();
      ops = 0;
    }

    // Either wipe the range for a clean regeneration, or keep what's already
    // scheduled (those slots are skipped and don't advance any rotation).
    final keepSlots = <String>{};
    final keptShifts = <PlannedShift>[];
    if (replaceExisting) {
      for (final doc in existingSnap.docs) {
        batch.delete(doc.reference);
        ops++;
        await flushIfFull();
      }
    } else {
      for (final shift in existing) {
        keepSlots.add('${shift.dateKey}|${shift.typeId}');
        if (shift.pharmacistId.isNotEmpty) keptShifts.add(toPlanned(shift));
      }
    }

    final byId = {for (final p in pharmacists) p.id: p};
    final plan = planSchedule(
      first: first,
      last: last,
      types: types,
      queue: pharmacists,
      holidayKeys: holidayKeys,
      keepSlots: keepSlots,
      keptShifts: keptShifts,
      priorTail: priorTail,
    );

    // Each shift created this run, mirrored into the original baseline below.
    final generated = <Shift>[];
    for (final p in plan) {
      final shift = Shift(
        id: '',
        dateKey: p.dateKey,
        typeId: p.typeId,
        start: p.start,
        end: p.end,
        pharmacist: byId[p.pharmacistId]?.fullName ?? '',
        pharmacistId: p.pharmacistId,
        createdBy: createdBy,
      );
      batch.set(_shifts.doc(), shift.toMap());
      generated.add(shift);
      ops++;
      await flushIfFull();
    }
    if (ops > 0) await batch.commit();

    await _snapshotOriginal(
      first: first,
      last: last,
      generated: generated,
      replaceExisting: replaceExisting,
    );
    return generated.length;
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

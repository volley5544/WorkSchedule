import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:work_schedule/models/pharmacist.dart';
import 'package:work_schedule/models/shift_type.dart';
import 'package:work_schedule/services/schedule_planner.dart';

void main() {
  // June 2026: 06-01 is a Monday, so 06-04/06-11 are Thursdays and
  // 06-06/06-07/06-13/06-14 are weekend days.
  List<Pharmacist> queueOf(int n) =>
      [for (var i = 1; i <= n; i++) Pharmacist(id: 'p$i', name: 'P$i', queue: i)];

  ShiftType type({
    String id = 't',
    List<int> days = ShiftType.everyDay,
    bool onHoliday = false,
    List<RosterEntry> roster = const [],
    Map<int, String> weekdayPins = const {},
    String followsTypeId = '',
    int sortOrder = 0,
    String start = '08:00',
    String end = '16:00',
  }) =>
      ShiftType(
        id: id,
        label: id,
        start: start,
        end: end,
        color: const Color(0xFF000000),
        days: days,
        onHoliday: onHoliday,
        roster: roster,
        weekdayPins: weekdayPins,
        followsTypeId: followsTypeId,
        sortOrder: sortOrder,
      );

  /// Index a plan by `'dateKey|typeId'` → pharmacistId for easy assertions.
  Map<String, String> bySlot(List<PlannedShift> plan) =>
      {for (final s in plan) '${s.dateKey}|${s.typeId}': s.pharmacistId};

  PlannedShift planned(String dateKey, String typeId, String pid,
          [String start = '08:00', String end = '16:00']) =>
      PlannedShift(
          dateKey: dateKey,
          typeId: typeId,
          pharmacistId: pid,
          start: start,
          end: end);

  test('Pharmacist.byShowOrder: set ones lead, unset fall back to queue', () {
    final list = [
      Pharmacist(id: 'a', name: 'A', queue: 1, showOrder: 0),
      Pharmacist(id: 'b', name: 'B', queue: 2, showOrder: 2),
      Pharmacist(id: 'c', name: 'C', queue: 3, showOrder: 1),
      Pharmacist(id: 'd', name: 'D', queue: 4, showOrder: 0),
    ]..sort(Pharmacist.byShowOrder);
    // showOrder 1, 2 first; then the unset (0) ones by queue (1 before 4).
    expect(list.map((p) => p.id).toList(), ['c', 'b', 'a', 'd']);
  });

  test('part-time pharmacists are excluded from the default rotation', () {
    final plan = planSchedule(
      first: DateTime(2026, 6, 1), // Mon
      last: DateTime(2026, 6, 3),
      types: [type()],
      queue: [
        Pharmacist(id: 'p1', name: 'P1', queue: 1),
        Pharmacist(id: 'p2', name: 'P2', queue: 2, partTime: true),
        Pharmacist(id: 'p3', name: 'P3', queue: 3),
      ],
      holidayKeys: const {},
    );
    final slot = bySlot(plan);
    // p2 is part-time, so the default rotation uses only p1 and p3.
    expect(slot['2026-06-01|t'], 'p1');
    expect(slot['2026-06-02|t'], 'p3');
    expect(slot['2026-06-03|t'], 'p1');
    expect(plan.any((s) => s.pharmacistId == 'p2'), isFalse);
  });

  test('a custom roster can still include a part-time pharmacist', () {
    final ptShift = type(roster: const [RosterEntry(pharmacistId: 'p2')]);
    final plan = planSchedule(
      first: DateTime(2026, 6, 1),
      last: DateTime(2026, 6, 1),
      types: [ptShift],
      queue: [
        Pharmacist(id: 'p1', name: 'P1', queue: 1),
        Pharmacist(id: 'p2', name: 'P2', queue: 2, partTime: true),
      ],
      holidayKeys: const {},
    );
    expect(bySlot(plan)['2026-06-01|t'], 'p2');
  });

  test('weekday and weekend buckets rotate independently', () {
    final plan = planSchedule(
      first: DateTime(2026, 6, 1), // Mon
      last: DateTime(2026, 6, 7), // Sun
      types: [type()],
      queue: queueOf(3),
      holidayKeys: const {},
    );
    final slot = bySlot(plan);
    // Weekdays Mon–Fri cycle p1,p2,p3,p1,p2.
    expect(slot['2026-06-01|t'], 'p1');
    expect(slot['2026-06-02|t'], 'p2');
    expect(slot['2026-06-03|t'], 'p3');
    expect(slot['2026-06-04|t'], 'p1');
    expect(slot['2026-06-05|t'], 'p2');
    // Weekend has its OWN counter, so Sat/Sun restart at p1,p2.
    expect(slot['2026-06-06|t'], 'p1');
    expect(slot['2026-06-07|t'], 'p2');
  });

  test('rotation continues from the prior-month tail per bucket', () {
    final plan = planSchedule(
      first: DateTime(2026, 6, 1), // Mon
      last: DateTime(2026, 6, 2),
      types: [type()],
      queue: queueOf(3),
      holidayKeys: const {},
      // Last weekday shift went to p2, so the next weekday is p3.
      priorTail: [planned('2026-05-29', 't', 'p2')], // Fri
    );
    final slot = bySlot(plan);
    expect(slot['2026-06-01|t'], 'p3');
    expect(slot['2026-06-02|t'], 'p1');
  });

  test('holiday is a non-working day: only onHoliday types run', () {
    final weekdayOnly = type(id: 'wd', days: const [1, 2, 3, 4, 5]);
    final holidayType =
        type(id: 'hd', days: const [1, 2, 3, 4, 5], onHoliday: true);
    final plan = planSchedule(
      first: DateTime(2026, 6, 2), // Tue, marked as a holiday below
      last: DateTime(2026, 6, 2),
      types: [weekdayOnly, holidayType],
      queue: queueOf(2),
      holidayKeys: {'2026-06-02'},
    );
    final slot = bySlot(plan);
    expect(slot.containsKey('2026-06-02|wd'), isFalse,
        reason: 'weekday-only type must be skipped on a holiday');
    expect(slot['2026-06-02|hd'], 'p1');
  });

  test('conflict-skip avoids overlapping double-booking', () {
    final yen = type(id: 'y', start: '16:30', end: '20:30', sortOrder: 1);
    final baai = type(id: 'b', start: '16:30', end: '23:30', sortOrder: 2);
    final plan = planSchedule(
      first: DateTime(2026, 6, 1),
      last: DateTime(2026, 6, 1),
      types: [yen, baai],
      queue: queueOf(3),
      holidayKeys: const {},
    );
    final slot = bySlot(plan);
    // ย takes p1; บ would also start at p1 but overlaps, so it skips to p2.
    expect(slot['2026-06-01|y'], 'p1');
    expect(slot['2026-06-01|b'], 'p2');
  });

  test('a night shift on a weekday is allowed (17h chain into next day)', () {
    // Mon ด 23:30→08:30 then Tue normal work 08:30–16:30 = 17h continuous, so
    // the night shift can be assigned.
    final night = type(id: 'd', start: '23:30', end: '08:30');
    final plan = planSchedule(
      first: DateTime(2026, 6, 1), // Mon
      last: DateTime(2026, 6, 1),
      types: [night],
      queue: queueOf(2),
      holidayKeys: const {},
    );
    expect(bySlot(plan)['2026-06-01|d'], 'p1');
  });

  test('after a night shift, the next weekday cannot add an evening shift', () {
    // The user's case: p1 did Mon normal work + Mon night (→Tue 08:30) + Tue
    // normal work = 17h. A Tue evening ย would extend that to 21h, so p1 is
    // skipped and ย goes to p2.
    final yen = type(id: 'y', start: '16:30', end: '20:30');
    final plan = planSchedule(
      first: DateTime(2026, 6, 2), // Tue
      last: DateTime(2026, 6, 2),
      types: [yen],
      queue: queueOf(2),
      holidayKeys: const {},
      keptShifts: [planned('2026-06-01', 'd', 'p1', '23:30', '08:30')],
    );
    expect(bySlot(plan)['2026-06-02|y'], 'p2');
  });

  test('a weekday allows only one scheduled shift on top of normal work', () {
    // Tue: normal work + ย = 2 (ok). A night ด would make it 3, so it skips to
    // the next person — even though ด on its own is a separate <18h chain.
    final yen = type(id: 'y', start: '16:30', end: '20:30', sortOrder: 1);
    final night = type(id: 'd', start: '23:30', end: '08:30', sortOrder: 2);
    final plan = planSchedule(
      first: DateTime(2026, 6, 2), // Tue
      last: DateTime(2026, 6, 2),
      types: [yen, night],
      queue: queueOf(2),
      holidayKeys: const {},
    );
    final slot = bySlot(plan);
    expect(slot['2026-06-02|y'], 'p1'); // normal + ย = 2 duty items
    expect(slot['2026-06-02|d'], 'p2'); // p1 would be normal + ย + ด = 3
  });

  test('a weekend allows two scheduled shifts but caps at the third', () {
    // No normal work on a weekend, so ช + บ = 2 is fine, but ด makes 3.
    final ch =
        type(id: 'ch', days: const [6, 7], start: '08:30', end: '16:30');
    final baai = type(
        id: 'b',
        days: const [6, 7],
        start: '16:30',
        end: '23:30',
        sortOrder: 1);
    final night = type(
        id: 'd',
        days: const [6, 7],
        start: '23:30',
        end: '08:30',
        sortOrder: 2);
    final plan = planSchedule(
      first: DateTime(2026, 6, 6), // Sat
      last: DateTime(2026, 6, 6),
      types: [ch, baai, night],
      queue: queueOf(2),
      holidayKeys: const {},
    );
    final slot = bySlot(plan);
    expect(slot['2026-06-06|ch'], 'p1');
    expect(slot['2026-06-06|b'], 'p1'); // ช + บ = 2 duty items, allowed
    expect(slot['2026-06-06|d'], 'p2'); // p1 would be 3 → skipped
  });

  test('without the prior night shift, the weekday evening shift is fine', () {
    // Same Tue evening shift, but p1 has no Mon night: Tue normal + ย = 12h.
    final yen = type(id: 'y', start: '16:30', end: '20:30');
    final plan = planSchedule(
      first: DateTime(2026, 6, 2),
      last: DateTime(2026, 6, 2),
      types: [yen],
      queue: queueOf(2),
      holidayKeys: const {},
    );
    expect(bySlot(plan)['2026-06-02|y'], 'p1');
  });

  test('weekday normal work counts toward the cap (configurable)', () {
    // With the cap raised to 24h, the 21h night→next-day-evening chain that was
    // blocked above is now allowed, so ย stays on p1.
    final yen = type(id: 'y', start: '16:30', end: '20:30');
    final plan = planSchedule(
      first: DateTime(2026, 6, 2),
      last: DateTime(2026, 6, 2),
      types: [yen],
      queue: queueOf(2),
      holidayKeys: const {},
      keptShifts: [planned('2026-06-01', 'd', 'p1', '23:30', '08:30')],
      maxDailySpanHours: 24,
    );
    expect(bySlot(plan)['2026-06-02|y'], 'p1');
  });

  test('custom roster order overrides the global queue', () {
    final reordered = type(roster: const [
      RosterEntry(pharmacistId: 'p3'),
      RosterEntry(pharmacistId: 'p1'),
      RosterEntry(pharmacistId: 'p2'),
    ]);
    final plan = planSchedule(
      first: DateTime(2026, 6, 1),
      last: DateTime(2026, 6, 3),
      types: [reordered],
      queue: queueOf(3),
      holidayKeys: const {},
    );
    final slot = bySlot(plan);
    expect(slot['2026-06-01|t'], 'p3');
    expect(slot['2026-06-02|t'], 'p1');
    expect(slot['2026-06-03|t'], 'p2');
  });

  test('weekday-constrained roster entry only runs on its weekday', () {
    // p1 only does this type on Thursdays; nobody else is in the roster.
    final thursdayOnly =
        type(roster: const [RosterEntry(pharmacistId: 'p1', weekdays: [4])]);
    final plan = planSchedule(
      first: DateTime(2026, 6, 1), // Mon
      last: DateTime(2026, 6, 14),
      types: [thursdayOnly],
      queue: queueOf(3),
      holidayKeys: const {},
    );
    final slot = bySlot(plan);
    // Thursdays only.
    expect(slot['2026-06-04|t'], 'p1');
    expect(slot['2026-06-11|t'], 'p1');
    // Any non-Thursday slot is empty (nobody eligible).
    expect(slot.containsKey('2026-06-01|t'), isFalse);
    expect(slot.containsKey('2026-06-05|t'), isFalse);
    expect(slot.length, 2);
  });

  test('month-week constraint: only the 5th Saturday', () {
    // p1 only does this Saturday shift on the 5th Saturday of the month.
    // August 2026 has Saturdays on 1, 8, 15, 22, 29 — the 29th is the 5th.
    final fifthSatOnly = type(
      days: const [6],
      roster: const [
        RosterEntry(pharmacistId: 'p1', weekdays: [6], monthWeeks: [5]),
      ],
    );
    final plan = planSchedule(
      first: DateTime(2026, 8, 1),
      last: DateTime(2026, 8, 31),
      types: [fifthSatOnly],
      queue: queueOf(3),
      holidayKeys: const {},
    );
    final slot = bySlot(plan);
    expect(slot['2026-08-29|t'], 'p1'); // 5th Saturday → assigned
    // Earlier Saturdays have nobody eligible, so they stay empty.
    for (final d in ['2026-08-01', '2026-08-08', '2026-08-15', '2026-08-22']) {
      expect(slot.containsKey('$d|t'), isFalse);
    }
  });

  test('month-week constraint: 1st–4th Saturdays only (skip a 5th)', () {
    final firstFourSats = type(
      days: const [6],
      roster: const [
        RosterEntry(pharmacistId: 'p1', weekdays: [6], monthWeeks: [1, 2, 3, 4]),
      ],
    );
    final plan = planSchedule(
      first: DateTime(2026, 8, 1),
      last: DateTime(2026, 8, 31),
      types: [firstFourSats],
      queue: queueOf(3),
      holidayKeys: const {},
    );
    final slot = bySlot(plan);
    expect(slot['2026-08-01|t'], 'p1');
    expect(slot['2026-08-22|t'], 'p1');
    expect(slot.containsKey('2026-08-29|t'), isFalse); // 5th Saturday skipped
  });

  test('week-parity entry only runs on its alternating week', () {
    final weekAThursday = type(roster: const [
      RosterEntry(pharmacistId: 'p1', weekdays: [4], parity: WeekParity.weekA),
    ]);
    final plan = planSchedule(
      first: DateTime(2026, 6, 1),
      last: DateTime(2026, 6, 14),
      types: [weekAThursday],
      queue: queueOf(3),
      holidayKeys: const {},
    );
    final assignedDays =
        plan.map((s) => parseDateKey(s.dateKey)).toList();
    // Exactly the Thursdays whose week index is even (Week A) get assigned.
    final thursdays = [DateTime(2026, 6, 4), DateTime(2026, 6, 11)];
    final expected =
        thursdays.where((d) => weekParityIndex(d).isEven).toList();
    expect(assignedDays, expected);
  });

  test('a holiday-only type (no active days) skips normal days', () {
    // onHoliday with empty days = holiday-only: must not appear on a weekday.
    final holidayOnly = type(days: const [], onHoliday: true);
    final plan = planSchedule(
      first: DateTime(2026, 6, 1), // Mon (not a holiday)
      last: DateTime(2026, 6, 2), // Tue holiday
      types: [holidayOnly],
      queue: queueOf(3),
      holidayKeys: {'2026-06-02'},
    );
    final slot = bySlot(plan);
    expect(slot.containsKey('2026-06-01|t'), isFalse); // normal day → skipped
    expect(slot['2026-06-02|t'], 'p1'); // holiday → runs
  });

  test('weekday pin fixes a pharmacist on a normal weekday', () {
    // Tue (weekday 2) is pinned to p3 on ordinary (non-holiday) days.
    final pinned = type(weekdayPins: {2: 'p3'});
    final plan = planSchedule(
      first: DateTime(2026, 6, 2), // Tue, not a holiday
      last: DateTime(2026, 6, 2),
      types: [pinned],
      queue: queueOf(3),
      holidayKeys: const {},
    );
    expect(bySlot(plan)['2026-06-02|t'], 'p3');
  });

  test('weekday pin also applies when the weekday is a holiday', () {
    final pinned = type(onHoliday: true, weekdayPins: {2: 'p3'});
    final plan = planSchedule(
      first: DateTime(2026, 6, 2), // Tue holiday
      last: DateTime(2026, 6, 2),
      types: [pinned],
      queue: queueOf(3),
      holidayKeys: {'2026-06-02'},
    );
    expect(bySlot(plan)['2026-06-02|t'], 'p3');
  });

  test('a pin does not advance the rotation counter', () {
    // Tue is pinned to p3; the next (unpinned) day still starts at p1.
    final pinned = type(weekdayPins: {2: 'p3'});
    final plan = planSchedule(
      first: DateTime(2026, 6, 2), // Tue (pinned)
      last: DateTime(2026, 6, 3), // Wed (rotation)
      types: [pinned],
      queue: queueOf(3),
      holidayKeys: const {},
    );
    final slot = bySlot(plan);
    expect(slot['2026-06-02|t'], 'p3');
    expect(slot['2026-06-03|t'], 'p1');
  });

  test('unpinned weekday falls back to the rotation', () {
    final pinned = type(weekdayPins: {2: 'p3'});
    final plan = planSchedule(
      first: DateTime(2026, 6, 3), // Wed (weekday 3, unpinned)
      last: DateTime(2026, 6, 3),
      types: [pinned],
      queue: queueOf(3),
      holidayKeys: const {},
    );
    expect(bySlot(plan)['2026-06-03|t'], 'p1');
  });

  test('other types skip a pinned pharmacist to avoid double-booking', () {
    // บ pins p1 on Tuesdays; ย rotates and must skip p1 (overlapping).
    final baai = type(
        id: 'b',
        start: '16:30',
        end: '23:30',
        weekdayPins: {2: 'p1'},
        sortOrder: 1);
    final yen = type(id: 'y', start: '16:30', end: '20:30', sortOrder: 2);
    final plan = planSchedule(
      first: DateTime(2026, 6, 2), // Tue
      last: DateTime(2026, 6, 2),
      types: [baai, yen],
      queue: queueOf(3),
      holidayKeys: const {},
    );
    final slot = bySlot(plan);
    expect(slot['2026-06-02|b'], 'p1'); // pinned
    expect(slot['2026-06-02|y'], 'p2'); // skipped p1
  });

  test('a linked type follows its leader on weekends but rotates on weekdays',
      () {
    // ช runs only on weekends; บ runs every day and follows ช. On weekends one
    // person gets both; on weekdays (no ช) บ rotates as the normal evening shift.
    final ch = type(
        id: 'ch',
        days: const [6, 7],
        start: '08:30',
        end: '16:30',
        sortOrder: 0);
    final baai = type(
        id: 'b',
        start: '16:30',
        end: '23:30',
        followsTypeId: 'ch',
        sortOrder: 2);
    final plan = planSchedule(
      first: DateTime(2026, 6, 1), // Mon
      last: DateTime(2026, 6, 7), // Sun
      types: [ch, baai],
      queue: queueOf(3),
      holidayKeys: const {},
    );
    final slot = bySlot(plan);
    // Weekdays: no ช; บ rotates independently p1,p2,p3,p1,p2.
    expect(slot.containsKey('2026-06-01|ch'), isFalse);
    expect(slot['2026-06-01|b'], 'p1');
    expect(slot['2026-06-05|b'], 'p2');
    // Weekend: ช rotates (Sat p1, Sun p2) and บ copies the same person.
    expect(slot['2026-06-06|ch'], 'p1');
    expect(slot['2026-06-06|b'], 'p1');
    expect(slot['2026-06-07|ch'], 'p2');
    expect(slot['2026-06-07|b'], 'p2');
  });

  test('kept slots are not overwritten and do not advance the counter', () {
    final plan = planSchedule(
      first: DateTime(2026, 6, 1),
      last: DateTime(2026, 6, 2),
      types: [type()],
      queue: queueOf(3),
      holidayKeys: const {},
      keepSlots: {'2026-06-01|t'},
      keptShifts: [planned('2026-06-01', 't', 'p2')],
    );
    final slot = bySlot(plan);
    // 06-01 was kept (not re-emitted); the counter never advanced, so 06-02
    // still starts at p1.
    expect(slot.containsKey('2026-06-01|t'), isFalse);
    expect(slot['2026-06-02|t'], 'p1');
  });
}

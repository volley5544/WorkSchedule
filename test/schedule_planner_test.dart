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
    bool singleRotation = false,
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
        singleRotation: singleRotation,
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

  test('singleRotation: one continuous rotation across every day incl holiday',
      () {
    // ด runs every day on one shared counter; weekend/holiday don't reset it.
    // June 2026: 06-01 Mon … 06-07 Sun, with 06-03 (Wed) marked a holiday.
    final night = type(id: 'd', singleRotation: true, days: const [1, 2, 3]);
    final plan = planSchedule(
      first: DateTime(2026, 6, 1),
      last: DateTime(2026, 6, 7),
      types: [night],
      queue: queueOf(3),
      holidayKeys: {'2026-06-03'},
    );
    final slot = bySlot(plan);
    // Continuous p1,p2,p3,p1,… across weekday/holiday/weekend with no reset,
    // and it runs even on days outside `days` (Sat/Sun) and on the holiday.
    expect(slot['2026-06-01|d'], 'p1');
    expect(slot['2026-06-02|d'], 'p2');
    expect(slot['2026-06-03|d'], 'p3'); // holiday — same rotation, not reset
    expect(slot['2026-06-04|d'], 'p1');
    expect(slot['2026-06-05|d'], 'p2');
    expect(slot['2026-06-06|d'], 'p3'); // Saturday — still runs, still continuous
    expect(slot['2026-06-07|d'], 'p1');
  });

  test('singleRotation continues from the prior month tail', () {
    final night = type(id: 'd', singleRotation: true);
    final plan = planSchedule(
      first: DateTime(2026, 6, 1),
      last: DateTime(2026, 6, 2),
      types: [night],
      queue: queueOf(3),
      holidayKeys: const {},
      priorTail: [planned('2026-05-31', 'd', 'p2')], // last night → next is p3
    );
    final slot = bySlot(plan);
    expect(slot['2026-06-01|d'], 'p3');
    expect(slot['2026-06-02|d'], 'p1');
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

  test('no overlap check: each type rotates independently from its own counter',
      () {
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
    // Both counters start at p1; the planner no longer skips the overlap, so
    // both land on p1 (the roster UI flags this day instead).
    expect(slot['2026-06-01|y'], 'p1');
    expect(slot['2026-06-01|b'], 'p1');
  });

  test('a night shift is assigned to the first person in rotation', () {
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

  test('no continuous-hours cap: a prior night shift no longer blocks next day',
      () {
    // p1 worked Mon night (→Tue 08:30); a Tue evening ย used to be blocked by
    // the old 18h cap. With the cap removed, the rotation just starts at p1.
    final yen = type(id: 'y', start: '16:30', end: '20:30');
    final plan = planSchedule(
      first: DateTime(2026, 6, 2), // Tue
      last: DateTime(2026, 6, 2),
      types: [yen],
      queue: queueOf(2),
      holidayKeys: const {},
      keptShifts: [planned('2026-06-01', 'd', 'p1', '23:30', '08:30')],
    );
    expect(bySlot(plan)['2026-06-02|y'], 'p1');
  });

  test('no per-day cap: a weekday person may take both an evening and a night',
      () {
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
    expect(slot['2026-06-02|y'], 'p1');
    expect(slot['2026-06-02|d'], 'p1'); // no per-day cap → same person is fine
  });

  test('no per-day cap: one weekend person may take ch + b + d (a full 24h)',
      () {
    // Each type's rotation starts at p1 and the shifts don't overlap, so all
    // three land on p1 — a full 24h, now permitted.
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
    expect(slot['2026-06-06|b'], 'p1');
    expect(slot['2026-06-06|d'], 'p1'); // 3 shifts on one person now allowed
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

  test('part-timer (weeks 1-4) is primary; normal only fills the 5th Saturday',
      () {
    // ชส on Saturdays: part-timer pt is constrained to the 1st–4th Saturdays;
    // a normal pharmacist p1 is in the roster unconstrained. The part-timer
    // must take weeks 1–4 and the normal must NOT appear there — the normal
    // only fills the 5th Saturday the part-timer is constrained out of.
    // August 2026 Saturdays: 1, 8, 15, 22 (weeks 1–4) and 29 (the 5th).
    final cs = type(
      days: const [6],
      roster: const [
        RosterEntry(pharmacistId: 'pt', weekdays: [6], monthWeeks: [1, 2, 3, 4]),
        RosterEntry(pharmacistId: 'p1'),
      ],
    );
    final plan = planSchedule(
      first: DateTime(2026, 8, 1),
      last: DateTime(2026, 8, 31),
      types: [cs],
      queue: [
        Pharmacist(id: 'p1', name: 'P1', queue: 1),
        Pharmacist(id: 'pt', name: 'PT', queue: 2, partTime: true),
      ],
      holidayKeys: const {},
    );
    final slot = bySlot(plan);
    for (final d in ['2026-08-01', '2026-08-08', '2026-08-15', '2026-08-22']) {
      expect(slot['$d|t'], 'pt', reason: 'weeks 1–4 belong to the part-timer');
    }
    expect(slot['2026-08-29|t'], 'p1', reason: '5th Saturday falls to normal');
  });

  test('two part-timers rotate among themselves across weeks 1-4', () {
    // Two part-timers both constrained to weeks 1–4 alternate; the normal still
    // only gets the 5th Saturday.
    final cs = type(
      days: const [6],
      roster: const [
        RosterEntry(pharmacistId: 'pa', weekdays: [6], monthWeeks: [1, 2, 3, 4]),
        RosterEntry(pharmacistId: 'pb', weekdays: [6], monthWeeks: [1, 2, 3, 4]),
        RosterEntry(pharmacistId: 'p1'),
      ],
    );
    final plan = planSchedule(
      first: DateTime(2026, 8, 1),
      last: DateTime(2026, 8, 31),
      types: [cs],
      queue: [
        Pharmacist(id: 'p1', name: 'P1', queue: 1),
        Pharmacist(id: 'pa', name: 'PA', queue: 2, partTime: true),
        Pharmacist(id: 'pb', name: 'PB', queue: 3, partTime: true),
      ],
      holidayKeys: const {},
    );
    final slot = bySlot(plan);
    expect(slot['2026-08-01|t'], 'pa');
    expect(slot['2026-08-08|t'], 'pb');
    expect(slot['2026-08-15|t'], 'pa');
    expect(slot['2026-08-22|t'], 'pb');
    expect(slot['2026-08-29|t'], 'p1'); // 5th Saturday → normal
  });

  test('a constrained 5th-Saturday entry wins over the open rotation', () {
    // The reported case: a custom rotation of mostly unconstrained pharmacists
    // plus one (p3) restricted to the 5th Saturday. The open rotation fills the
    // 1st–4th Saturdays; on the 5th, the constrained p3 must take it instead of
    // whichever unconstrained pharmacist's turn it is.
    final sat = type(
      days: const [6],
      roster: const [
        RosterEntry(pharmacistId: 'p1'),
        RosterEntry(pharmacistId: 'p2'),
        RosterEntry(pharmacistId: 'p3', weekdays: [6], monthWeeks: [5]),
      ],
    );
    final plan = planSchedule(
      first: DateTime(2026, 8, 1),
      last: DateTime(2026, 8, 31),
      types: [sat],
      queue: queueOf(3),
      holidayKeys: const {},
    );
    final slot = bySlot(plan);
    // 1st–4th Saturdays: the open rotation (p1, p2) — p3 never appears there.
    expect(slot['2026-08-01|t'], 'p1');
    expect(slot['2026-08-08|t'], 'p2');
    expect(slot['2026-08-15|t'], 'p1');
    expect(slot['2026-08-22|t'], 'p2');
    // 5th Saturday: the constrained p3 wins.
    expect(slot['2026-08-29|t'], 'p3');
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

  test('other types no longer skip a pinned pharmacist (no overlap check)', () {
    // บ pins p1 on Tuesdays; ย rotates from its own counter (also p1). With no
    // overlap check, ย stays on p1 even though it overlaps บ.
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
    expect(slot['2026-06-02|y'], 'p1'); // no skip → also p1
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

  test('a Friday-holiday pin + link may stack ch + b + d on one person (24h)',
      () {
    // Oct 23 2026 is a Friday AND a holiday, so the onHoliday morning/evening/
    // night types all run. ช rotates to p1, บ follows ช (→ p1), and ด is pinned
    // to p1 on Fridays. With no per-day/hours cap, all three stay on p1 — the
    // pin and link are honoured. (Only an *overlap* would make them fall
    // through, and these three don't overlap.)
    final ch = type(
        id: 'ch',
        days: const [6, 7],
        onHoliday: true,
        start: '08:30',
        end: '16:30',
        sortOrder: 0);
    final baai = type(
        id: 'b',
        onHoliday: true,
        followsTypeId: 'ch',
        start: '16:30',
        end: '23:30',
        sortOrder: 1);
    final night = type(
        id: 'd',
        onHoliday: true,
        weekdayPins: {DateTime.friday: 'p1'},
        start: '23:30',
        end: '08:30',
        sortOrder: 2);
    final plan = planSchedule(
      first: DateTime(2026, 10, 23), // Friday, marked holiday below
      last: DateTime(2026, 10, 23),
      types: [ch, baai, night],
      queue: queueOf(3),
      holidayKeys: {'2026-10-23'},
    );
    final slot = bySlot(plan);
    expect(slot['2026-10-23|ch'], 'p1');
    expect(slot['2026-10-23|b'], 'p1'); // follows ช → p1
    expect(slot['2026-10-23|d'], 'p1'); // Friday pin honoured → p1 (24h)
  });

  test('a pin is honoured even when it overlaps another shift (no overlap check)',
      () {
    // บ rotates to p1; a Friday pin also puts p1 on ย, which overlaps บ. The
    // planner no longer skips it — both stay on p1 (the roster UI flags it).
    final baai = type(
        id: 'b',
        onHoliday: true,
        start: '16:30',
        end: '23:30',
        sortOrder: 0);
    final yen = type(
        id: 'y',
        onHoliday: true,
        weekdayPins: {DateTime.friday: 'p1'},
        start: '16:30',
        end: '20:30',
        sortOrder: 1);
    final plan = planSchedule(
      first: DateTime(2026, 10, 23), // Friday holiday
      last: DateTime(2026, 10, 23),
      types: [baai, yen],
      queue: queueOf(3),
      holidayKeys: {'2026-10-23'},
    );
    final slot = bySlot(plan);
    expect(slot['2026-10-23|b'], 'p1');
    expect(slot['2026-10-23|y'], 'p1'); // pin honoured despite overlap
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

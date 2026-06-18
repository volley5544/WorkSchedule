import 'package:flutter_test/flutter_test.dart';
import 'package:work_schedule/models/shift.dart';
import 'package:work_schedule/services/shift_conflicts.dart';

void main() {
  Shift shift(String dateKey, String start, String end) => Shift(
        id: '',
        dateKey: dateKey,
        typeId: 't',
        start: start,
        end: end,
        pharmacist: 'P1',
        pharmacistId: 'p1',
      );

  /// Builds a [shiftsFor] lookup from a date-keyed map of shifts.
  List<Shift> Function(DateTime) lookup(Map<String, List<Shift>> byDay) =>
      (d) => byDay[Shift.keyFor(d)] ?? const [];

  test('a clean single shift on a weekend has no conflicts', () {
    final byDay = {
      '2026-06-06': [shift('2026-06-06', '08:30', '16:30')], // Sat
    };
    final c = conflictsForDay(
      day: DateTime(2026, 6, 6),
      shiftsFor: lookup(byDay),
      holidayKeys: const {},
    );
    expect(c, isEmpty);
  });

  test('more than two shifts on a day is flagged tooManyShifts', () {
    final byDay = {
      '2026-06-06': [
        shift('2026-06-06', '08:30', '16:30'),
        shift('2026-06-06', '16:30', '23:30'),
        shift('2026-06-06', '23:30', '08:30'),
      ],
    };
    final c = conflictsForDay(
      day: DateTime(2026, 6, 6),
      shiftsFor: lookup(byDay),
      holidayKeys: const {},
    );
    expect(c, contains(ShiftConflict.tooManyShifts));
  });

  test('ch + b + d on a weekend (24h) is both tooMany and tooLong', () {
    final byDay = {
      '2026-06-06': [
        shift('2026-06-06', '08:30', '16:30'),
        shift('2026-06-06', '16:30', '23:30'),
        shift('2026-06-06', '23:30', '08:30'),
      ],
    };
    final c = conflictsForDay(
      day: DateTime(2026, 6, 6),
      shiftsFor: lookup(byDay),
      holidayKeys: const {},
    );
    expect(c, containsAll([ShiftConflict.tooManyShifts, ShiftConflict.tooLong]));
    expect(c, isNot(contains(ShiftConflict.overlap))); // back-to-back, no overlap
  });

  test('weekday: normal work + 2 shifts counts as 3 → tooManyShifts', () {
    // Fri 2026-07-31: normal 08:30–16:30 + ณ 16:30–21:00 + ด 23:30–08:30 = 3
    // duty blocks, so the day is flagged even though only 2 shifts are stored.
    final byDay = {
      '2026-07-31': [
        shift('2026-07-31', '16:30', '21:00'), // ณ
        shift('2026-07-31', '23:30', '08:30'), // ด
      ],
    };
    final c = conflictsForDay(
      day: DateTime(2026, 7, 31), // Friday
      shiftsFor: lookup(byDay),
      holidayKeys: const {},
    );
    expect(c, contains(ShiftConflict.tooManyShifts));
  });

  test('weekday: normal work + 1 shift (2 duties) is NOT flagged', () {
    final byDay = {
      '2026-07-31': [shift('2026-07-31', '16:30', '21:00')], // Fri, one shift
    };
    final c = conflictsForDay(
      day: DateTime(2026, 7, 31),
      shiftsFor: lookup(byDay),
      holidayKeys: const {},
    );
    expect(c, isNot(contains(ShiftConflict.tooManyShifts)));
  });

  test('weekend: 2 shifts (no normal work) is NOT flagged as too many', () {
    final byDay = {
      '2026-06-06': [
        shift('2026-06-06', '08:30', '16:30'), // Sat ช
        shift('2026-06-06', '16:30', '23:30'), // บ
      ],
    };
    final c = conflictsForDay(
      day: DateTime(2026, 6, 6),
      shiftsFor: lookup(byDay),
      holidayKeys: const {},
    );
    expect(c, isNot(contains(ShiftConflict.tooManyShifts)));
  });

  test('overlapping shift times are flagged', () {
    final byDay = {
      '2026-06-06': [
        shift('2026-06-06', '16:30', '23:30'), // บ
        shift('2026-06-06', '16:30', '20:30'), // ย overlaps บ
      ],
    };
    final c = conflictsForDay(
      day: DateTime(2026, 6, 6),
      shiftsFor: lookup(byDay),
      holidayKeys: const {},
    );
    expect(c, contains(ShiftConflict.overlap));
  });

  test('touching shifts (b 16:30-23:30, d 23:30-08:30) do not count as overlap',
      () {
    final byDay = {
      '2026-06-06': [
        shift('2026-06-06', '16:30', '23:30'),
        shift('2026-06-06', '23:30', '08:30'),
      ],
    };
    final c = conflictsForDay(
      day: DateTime(2026, 6, 6),
      shiftsFor: lookup(byDay),
      holidayKeys: const {},
    );
    expect(c, isNot(contains(ShiftConflict.overlap)));
  });

  test('a lone weekday night shift (17h chain) is under the cap', () {
    // Tue ด 23:30→Wed 08:30 + Wed normal work to 16:30 = 17h. Tue normal work is
    // a separate earlier stretch. Nothing exceeds 18h.
    final byDay = {
      '2026-06-02': [shift('2026-06-02', '23:30', '08:30')], // Tue night
    };
    final c = conflictsForDay(
      day: DateTime(2026, 6, 2),
      shiftsFor: lookup(byDay),
      holidayKeys: const {},
    );
    expect(c, isNot(contains(ShiftConflict.tooLong)));
  });

  test('a night shift then next-day evening exceeds 18h continuous', () {
    // Tue ด 23:30→Wed 08:30, Wed normal 08:30–16:30, Wed ย 16:30–20:30 =
    // 23:30 Tue → 20:30 Wed = 21h continuous.
    final byDay = {
      '2026-06-02': [shift('2026-06-02', '23:30', '08:30')], // Tue night
      '2026-06-03': [shift('2026-06-03', '16:30', '20:30')], // Wed evening
    };
    final c = conflictsForDay(
      day: DateTime(2026, 6, 3),
      shiftsFor: lookup(byDay),
      holidayKeys: const {},
    );
    expect(c, contains(ShiftConflict.tooLong));
  });

  test('on a holiday there is no implicit normal work', () {
    // Same Tue night ด, but Wed is a holiday so no Wed normal work: the chain is
    // only 23:30→08:30 = 9h, not flagged.
    final byDay = {
      '2026-06-02': [shift('2026-06-02', '23:30', '08:30')],
    };
    final c = conflictsForDay(
      day: DateTime(2026, 6, 2),
      shiftsFor: lookup(byDay),
      holidayKeys: {'2026-06-02', '2026-06-03'},
    );
    expect(c, isNot(contains(ShiftConflict.tooLong)));
  });
}

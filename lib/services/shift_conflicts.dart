import '../models/shift.dart';

/// A single-day scheduling problem flagged on the roster for one pharmacist.
///
/// The auto-scheduler no longer prevents any of these (it fills every slot by
/// rotation); instead the roster UI highlights the day so a human can review
/// and fix it.
enum ShiftConflict {
  /// More than [maxShiftsPerDay] duty blocks on the day. The implicit Mon–Fri
  /// 08:30–16:30 normal work counts as one (skipped on holidays/weekends), so a
  /// weekday with two scheduled shifts on top of normal work is flagged.
  tooManyShifts,

  /// A continuous on-duty stretch longer than [maxSpanHours] hours — counting
  /// the implicit Mon–Fri 08:30–16:30 normal work and chaining shifts that touch
  /// across midnight (e.g. a night shift running into the next day's work).
  tooLong,

  /// Two of the day's shifts overlap in time.
  overlap,
}

/// Threshold: more than this many shifts in a day is flagged.
const maxShiftsPerDay = 2;

/// Threshold: a continuous on-duty stretch longer than this many hours is
/// flagged.
const maxSpanHours = 18;

/// The hospital's implicit weekday working hours (Mon–Fri 08:30–16:30) in
/// minutes past midnight; counted toward the continuous-hours check.
const _normalStart = 510; // 08:30
const _normalEnd = 990; // 16:30

int _toMinutes(String hhmm) {
  final parts = hhmm.split(':');
  return (int.tryParse(parts[0]) ?? 0) * 60 +
      (int.tryParse(parts.length > 1 ? parts[1] : '0') ?? 0);
}

int _daysSinceEpoch(DateTime day) => DateTime(day.year, day.month, day.day)
    .difference(DateTime(2024, 1, 1))
    .inDays;

/// A shift's [start]/[end] on [day] as an absolute `(start, end)` minute range,
/// normalising a cross-midnight end (ด 23:30–08:30) into the next day.
(int, int) _absInterval(DateTime day, String start, String end) {
  final base = _daysSinceEpoch(day) * 1440;
  final s = _toMinutes(start);
  var e = _toMinutes(end);
  if (e <= s) e += 1440;
  return (base + s, base + e);
}

/// The scheduling conflicts for one pharmacist on [day].
///
/// [shiftsFor] returns that pharmacist's shifts on any date — the previous and
/// next day are consulted so a night shift chaining into the next day's work is
/// measured correctly. [holidayKeys] are clinic-holiday `yyyy-MM-dd` keys; there
/// is no implicit normal work on a holiday. Returns an empty set when the day is
/// clean (or has no shifts).
Set<ShiftConflict> conflictsForDay({
  required DateTime day,
  required List<Shift> Function(DateTime) shiftsFor,
  required Set<String> holidayKeys,
}) {
  final today = shiftsFor(day);
  final out = <ShiftConflict>{};
  if (today.isEmpty) return out;

  // Whether this is a normal working day (Mon–Fri, not a holiday), on which the
  // implicit 08:30–16:30 desk work counts as a duty block.
  final isWorkday =
      day.weekday <= DateTime.friday && !holidayKeys.contains(Shift.keyFor(day));

  // (a) Too many duty blocks on the day — scheduled shifts plus the implicit
  // weekday normal work. So a weekday fits only one scheduled shift on top of
  // normal work; a weekend/holiday fits two scheduled shifts.
  if (today.length + (isWorkday ? 1 : 0) > maxShiftsPerDay) {
    out.add(ShiftConflict.tooManyShifts);
  }

  // (c) Overlap between any two of the day's shifts.
  final todayRanges = [for (final s in today) _absInterval(day, s.start, s.end)];
  overlapSearch:
  for (var i = 0; i < todayRanges.length; i++) {
    for (var j = i + 1; j < todayRanges.length; j++) {
      final a = todayRanges[i], b = todayRanges[j];
      if (a.$1 < b.$2 && b.$1 < a.$2) {
        out.add(ShiftConflict.overlap);
        break overlapSearch;
      }
    }
  }

  // (b) A continuous on-duty stretch over the hours cap. Gather this pharmacist's
  // intervals across the previous/this/next day (shifts + the implicit weekday
  // normal work), merge touching/overlapping ones, and flag a stretch that both
  // contains one of *today's* shifts and exceeds the cap.
  final intervals = <(int, int)>[];
  void addDay(DateTime d) {
    final key = Shift.keyFor(d);
    if (d.weekday <= DateTime.friday && !holidayKeys.contains(key)) {
      final base = _daysSinceEpoch(d) * 1440;
      intervals.add((base + _normalStart, base + _normalEnd));
    }
    for (final s in shiftsFor(d)) {
      intervals.add(_absInterval(d, s.start, s.end));
    }
  }

  addDay(DateTime(day.year, day.month, day.day - 1));
  addDay(day);
  addDay(DateTime(day.year, day.month, day.day + 1));
  intervals.sort((a, b) => a.$1.compareTo(b.$1));

  bool stretchTooLong(int start, int end) {
    if ((end - start) <= maxSpanHours * 60) return false;
    for (final r in todayRanges) {
      if (r.$1 >= start && r.$2 <= end) return true;
    }
    return false;
  }

  var start = intervals.first.$1;
  var end = intervals.first.$2;
  for (final iv in intervals.skip(1)) {
    if (iv.$1 <= end) {
      if (iv.$2 > end) end = iv.$2;
    } else {
      if (stretchTooLong(start, end)) {
        out.add(ShiftConflict.tooLong);
        break;
      }
      start = iv.$1;
      end = iv.$2;
    }
  }
  if (!out.contains(ShiftConflict.tooLong) && stretchTooLong(start, end)) {
    out.add(ShiftConflict.tooLong);
  }

  return out;
}

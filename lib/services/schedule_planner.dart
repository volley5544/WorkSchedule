import '../models/pharmacist.dart';
import '../models/shift_type.dart';

/// The day categories a shift rotates within. Each shift type keeps an
/// **independent** rotation counter per bucket, so (for example) weekday and
/// weekend duty for the same type advance separately.
enum DayBucket { weekday, weekend, holiday }

/// A single scheduled (or to-be-scheduled) assignment. Used both as the
/// planner's output and as its history/kept-shift inputs. Deliberately free of
/// Firestore types so the planner is pure and unit-testable.
class PlannedShift {
  const PlannedShift({
    required this.dateKey,
    required this.typeId,
    required this.pharmacistId,
    required this.start,
    required this.end,
  });

  final String dateKey;
  final String typeId;
  final String pharmacistId;
  final String start;
  final String end;
}

/// `yyyy-MM-dd` key for [day] (matches `Shift.keyFor`, duplicated here to keep
/// the planner independent of the Firestore-backed models).
String dateKeyFor(DateTime day) {
  String two(int v) => v.toString().padLeft(2, '0');
  return '${day.year.toString().padLeft(4, '0')}-${two(day.month)}-${two(day.day)}';
}

/// Parses a `yyyy-MM-dd` key back into a date-only [DateTime].
DateTime parseDateKey(String key) {
  final parts = key.split('-');
  return DateTime(
    int.parse(parts[0]),
    int.parse(parts[1]),
    int.parse(parts[2]),
  );
}

/// Which bucket [day] falls into, given the set of holiday date keys.
DayBucket bucketFor(DateTime day, Set<String> holidayKeys) {
  if (holidayKeys.contains(dateKeyFor(day))) return DayBucket.holiday;
  return day.weekday >= DateTime.saturday
      ? DayBucket.weekend
      : DayBucket.weekday;
}

/// Whether [type] is scheduled on [day] (already classified into [bucket]).
/// Holidays ignore the weekday list and use the [ShiftType.onHoliday] flag.
bool _typeRunsOn(ShiftType type, DateTime day, DayBucket bucket) =>
    bucket == DayBucket.holiday
        ? type.onHoliday
        : type.days.contains(day.weekday);

int _toMinutes(String hhmm) {
  final parts = hhmm.split(':');
  return (int.tryParse(parts[0]) ?? 0) * 60 +
      (int.tryParse(parts.length > 1 ? parts[1] : '0') ?? 0);
}

/// Whether two same-day time ranges overlap. Cross-midnight ranges (end ≤
/// start, e.g. ด 23:30–08:30) are normalised by adding a day to the end. Touch
/// at an endpoint does not count as overlap (บ 16:30–23:30 vs ด 23:30–08:30).
bool _timesOverlap(String s1, String e1, String s2, String e2) {
  var a1 = _toMinutes(s1), a2 = _toMinutes(e1);
  if (a2 <= a1) a2 += 1440;
  var b1 = _toMinutes(s2), b2 = _toMinutes(e2);
  if (b2 <= b1) b2 += 1440;
  return a1 < b2 && b1 < a2;
}

/// The hospital's normal weekday working hours (Mon–Fri 08:30–16:30). This is
/// not a scheduled shift, but it *is* time on duty, so it counts toward the
/// daily working-hours cap and can chain into an adjoining shift.
const _normalWorkStart = 510; // 08:30
const _normalWorkEnd = 990; // 16:30

/// Days between [day] and a fixed epoch (1 Jan 2024), so a shift's clock time
/// can be turned into an absolute minute value for cross-day chaining.
int _daysSinceEpoch(DateTime day) =>
    DateTime(day.year, day.month, day.day).difference(DateTime(2024, 1, 1)).inDays;

/// A shift's [start]/[end] on [day] as an absolute `(start, end)` minute range,
/// normalising a cross-midnight end (ด 23:30–08:30) into the next day.
(int, int) _absInterval(DateTime day, String start, String end) {
  final base = _daysSinceEpoch(day) * 1440;
  final s = _toMinutes(start);
  var e = _toMinutes(end);
  if (e <= s) e += 1440;
  return (base + s, base + e);
}

/// Builds the roster the auto-scheduler should write.
///
/// Walks every day in `first..last`. For each day it picks a bucket
/// (holiday → weekend → weekday) and, for each shift type that runs in that
/// bucket (in `sortOrder`), assigns the next eligible, non-conflicting
/// pharmacist from that type's rotation. Each `(type, bucket)` keeps its own
/// counter, seeded from [priorTail] so rotation continues across months.
///
/// - [queue] is the global pharmacist order, used when a type has no custom
///   roster.
/// - [keepSlots] holds `'$dateKey|$typeId'` slots that already exist and must be
///   left untouched (their counter is *not* advanced).
/// - [keptShifts] are existing in-range shifts; their times seed the
///   conflict map so new assignments don't double-book a pharmacist.
/// - [priorTail] are assignments dated before [first], used purely to seed each
///   bucket's starting pharmacist.
/// - [maxDailySpanHours] caps a pharmacist's *continuous* time on duty (default
///   18h). The timeline includes the implicit Mon–Fri 08:30–16:30 normal work
///   and chains shifts that touch across midnight (e.g. a night shift running
///   into the next day's normal work). A candidate that would push a continuous
///   stretch past the cap — or overlap an existing shift — is skipped for the
///   next person in the rotation.
/// - [maxShiftsPerDay] caps how many duty items a pharmacist may have on one
///   date (default 2). The implicit weekday normal work counts as one, so on a
///   weekday only a single scheduled shift fits on top of it; on weekends and
///   holidays two scheduled shifts (e.g. ช + บ) are allowed.
List<PlannedShift> planSchedule({
  required DateTime first,
  required DateTime last,
  required List<ShiftType> types,
  required List<Pharmacist> queue,
  required Set<String> holidayKeys,
  Set<String> keepSlots = const {},
  List<PlannedShift> keptShifts = const [],
  List<PlannedShift> priorTail = const [],
  int maxDailySpanHours = 18,
  int maxShiftsPerDay = 2,
}) {
  if (types.isEmpty || queue.isEmpty) return const [];
  final maxSpan = maxDailySpanHours * 60;

  final validIds = {for (final p in queue) p.id};
  final sortedTypes = [...types]
    ..sort((a, b) => a.sortOrder.compareTo(b.sortOrder));

  // Resolve each type's rotation participants once. A type with a custom roster
  // uses exactly the pharmacists listed (part-time included if added); the
  // default rotation uses the queue minus part-time pharmacists.
  final participantsByType = <String, List<RosterEntry>>{
    for (final type in sortedTypes)
      type.id: type.hasCustomRoster
          ? type.roster
              .where((e) => validIds.contains(e.pharmacistId))
              .toList()
          : [
              for (final p in queue)
                if (!p.partTime) RosterEntry(pharmacistId: p.id),
            ],
  };

  // Per (type, bucket) rotation pointer into the participant list.
  final counters = <String, int>{};
  String counterKey(String typeId, DayBucket bucket) => '$typeId|${bucket.name}';

  // Seed counters from the latest prior shift of each type in each bucket.
  for (final type in sortedTypes) {
    final participants = participantsByType[type.id]!;
    if (participants.isEmpty) continue;
    final prior = priorTail.where((s) => s.typeId == type.id).toList()
      ..sort((a, b) => a.dateKey.compareTo(b.dateKey));
    final lastByBucket = <DayBucket, String>{}; // bucket → pharmacistId
    for (final s in prior) {
      final date = parseDateKey(s.dateKey);
      // A pinned weekday pick is not part of the rotation, so it must not seed
      // the rotation counter for its bucket.
      if (type.weekdayPins.containsKey(date.weekday)) continue;
      lastByBucket[bucketFor(date, holidayKeys)] = s.pharmacistId;
    }
    lastByBucket.forEach((bucket, pharmacistId) {
      final idx = participants.indexWhere((e) => e.pharmacistId == pharmacistId);
      if (idx != -1) {
        counters[counterKey(type.id, bucket)] = (idx + 1) % participants.length;
      }
    });
  }

  // dateKey → assignments already on that day (for the daily limits below).
  final byDay = <String, List<PlannedShift>>{};
  for (final s in keptShifts) {
    byDay.putIfAbsent(s.dateKey, () => []).add(s);
  }

  // A pharmacist's on-duty intervals on [day]: their scheduled shifts plus,
  // on a normal weekday (not a holiday), the implicit 08:30–16:30 work that
  // everyone does. Absolute minutes, so they chain across midnight.
  List<(int, int)> intervalsOn(String pharmacistId, DateTime day) {
    final out = <(int, int)>[];
    final key = dateKeyFor(day);
    if (day.weekday <= DateTime.friday && !holidayKeys.contains(key)) {
      final base = _daysSinceEpoch(day) * 1440;
      out.add((base + _normalWorkStart, base + _normalWorkEnd));
    }
    for (final s in byDay[key] ?? const <PlannedShift>[]) {
      if (s.pharmacistId == pharmacistId) {
        out.add(_absInterval(day, s.start, s.end));
      }
    }
    return out;
  }

  // Whether assigning [type] to [pharmacistId] on [dateKey] is disallowed: it
  // would overlap one of their shifts, give them more than [maxShiftsPerDay]
  // duty items that day, or extend a *continuous* on-duty stretch (their work +
  // adjoining shifts, chaining across midnight) past [maxDailySpanHours]. Any of
  // these makes the caller skip to the next person.
  bool blocked(String dateKey, String pharmacistId, ShiftType type) {
    final day = parseDateKey(dateKey);

    // Count duty items already on this date: the implicit weekday normal work
    // counts as one, plus each scheduled shift the pharmacist holds. Adding the
    // candidate must not push the total over the per-day cap. (On weekends and
    // holidays there's no normal work, so two scheduled shifts are still fine.)
    var dutyCount = 1; // the candidate itself
    if (day.weekday <= DateTime.friday && !holidayKeys.contains(dateKey)) {
      dutyCount++; // normal 08:30–16:30 work
    }
    for (final s in byDay[dateKey] ?? const <PlannedShift>[]) {
      if (s.pharmacistId == pharmacistId) {
        if (_timesOverlap(type.start, type.end, s.start, s.end)) return true;
        dutyCount++;
      }
    }
    if (dutyCount > maxShiftsPerDay) return true;

    final candidate = _absInterval(day, type.start, type.end);
    // Gather their timeline over the candidate day and its neighbours (a night
    // shift chains into the next day's normal work), then add the candidate.
    final intervals = <(int, int)>[candidate];
    for (final offset in [-1, 0, 1]) {
      intervals.addAll(intervalsOn(
        pharmacistId,
        DateTime(day.year, day.month, day.day + offset),
      ));
    }
    intervals.sort((a, b) => a.$1.compareTo(b.$1));
    // Merge touching/overlapping intervals and find the stretch covering the
    // candidate; only that one can be pushed over the cap by this assignment.
    var start = intervals.first.$1;
    var end = intervals.first.$2;
    for (final iv in intervals.skip(1)) {
      if (iv.$1 <= end) {
        if (iv.$2 > end) end = iv.$2;
      } else {
        if (candidate.$1 >= start && candidate.$2 <= end) break;
        start = iv.$1;
        end = iv.$2;
      }
    }
    return start <= candidate.$1 &&
        candidate.$2 <= end &&
        (end - start) > maxSpan;
  }

  final result = <PlannedShift>[];
  for (
    var day = first;
    !day.isAfter(last);
    day = DateTime(day.year, day.month, day.day + 1)
  ) {
    final dateKey = dateKeyFor(day);
    final bucket = bucketFor(day, holidayKeys);
    for (final type in sortedTypes) {
      if (!_typeRunsOn(type, day, bucket)) continue;
      if (keepSlots.contains('$dateKey|${type.id}')) continue;

      void emit(String pharmacistId) {
        final shift = PlannedShift(
          dateKey: dateKey,
          typeId: type.id,
          pharmacistId: pharmacistId,
          start: type.start,
          end: type.end,
        );
        byDay.putIfAbsent(dateKey, () => []).add(shift);
        result.add(shift);
      }

      // Weekday pin: a pinned pharmacist replaces the rotation on this weekday
      // (on a normal day, weekend, or holiday alike). It is assigned as-is (an
      // explicit admin choice) and does NOT advance the bucket counter, but it
      // does join the conflict map so other types' rotations skip them.
      final pinned = type.weekdayPins[day.weekday];
      if (pinned != null && validIds.contains(pinned)) {
        emit(pinned);
        continue;
      }

      // Linked type: if its leader was scheduled today, copy that pharmacist
      // (one person covers both, e.g. บ follows ช on weekends/holidays) without
      // advancing this type's own rotation. On days the leader doesn't run, it
      // falls through to the normal rotation below.
      if (type.followsTypeId.isNotEmpty) {
        String? leader;
        for (final s in byDay[dateKey] ?? const <PlannedShift>[]) {
          if (s.typeId == type.followsTypeId) {
            leader = s.pharmacistId;
            break;
          }
        }
        if (leader != null) {
          emit(leader);
          continue;
        }
      }

      final participants = participantsByType[type.id]!;
      if (participants.isEmpty) continue;

      final ckey = counterKey(type.id, bucket);
      final ptr = (counters[ckey] ?? 0) % participants.length;

      // Scan forward for the first eligible, non-conflicting participant.
      int? chosen;
      for (var i = 0; i < participants.length; i++) {
        final idx = (ptr + i) % participants.length;
        final entry = participants[idx];
        if (!entry.eligibleOn(day)) continue;
        if (blocked(dateKey, entry.pharmacistId, type)) continue;
        chosen = idx;
        break;
      }
      if (chosen == null) continue; // nobody available: leave the slot empty

      counters[ckey] = (chosen + 1) % participants.length;
      emit(participants[chosen].pharmacistId);
    }
  }
  return result;
}

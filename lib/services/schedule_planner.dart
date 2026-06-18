import '../models/pharmacist.dart';
import '../models/shift_type.dart';

/// The day categories a shift rotates within. Each shift type keeps an
/// **independent** rotation counter per bucket, so (for example) weekday and
/// weekend duty for the same type advance separately. [all] is the single bucket
/// used by [ShiftType.singleRotation] types, which rotate continuously across
/// every day regardless of the calendar.
enum DayBucket { weekday, weekend, holiday, all }

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

/// Builds the roster the auto-scheduler should write.
///
/// Walks every day in `first..last`. For each day it picks a bucket
/// (holiday → weekend → weekday) and, for each shift type that runs in that
/// bucket (in `sortOrder`), assigns the next eligible pharmacist from that
/// type's rotation. Each `(type, bucket)` keeps its own counter, seeded from
/// [priorTail] so rotation continues across months.
///
/// - [queue] is the global pharmacist order, used when a type has no custom
///   roster.
/// - [keepSlots] holds `'$dateKey|$typeId'` slots that already exist and must be
///   left untouched (their counter is *not* advanced).
/// - [keptShifts] are existing in-range shifts; they're tracked per day so a
///   linked type can find its leader's pharmacist.
/// - [priorTail] are assignments dated before [first], used purely to seed each
///   bucket's starting pharmacist.
///
/// There are intentionally **no scheduling guards**: no cap on shifts per day,
/// no continuous-hours cap, and no overlap check — the rotation just fills every
/// slot. A pharmacist *can* end up with overlapping or back-to-back-to-exhaustion
/// duty; the roster UI flags those days for a human to review and fix.
List<PlannedShift> planSchedule({
  required DateTime first,
  required DateTime last,
  required List<ShiftType> types,
  required List<Pharmacist> queue,
  required Set<String> holidayKeys,
  Set<String> keepSlots = const {},
  List<PlannedShift> keptShifts = const [],
  List<PlannedShift> priorTail = const [],
}) {
  if (types.isEmpty || queue.isEmpty) return const [];

  final validIds = {for (final p in queue) p.id};
  final sortedTypes = [...types]
    ..sort((a, b) => a.sortOrder.compareTo(b.sortOrder));

  // Resolve each type's participants once, split into three priority tiers that
  // are tried in order each day:
  //   'cs' — constrained entries (a Day/week rule pins them to specific
  //          weekdays/weeks/parity). The admin asked for that person on those
  //          exact days, so when one is eligible it WINS over the open rotation
  //          (e.g. a "5th Saturday only" pharmacist gets the 5th Saturday; a
  //          part-timer restricted to the 1st–4th gets those weeks).
  //   'pt' — unconstrained part-timers (serve before the normal rotation).
  //   'nm' — unconstrained normals (the open rotation that fills the rest).
  // A type with a custom roster uses exactly the pharmacists listed; the default
  // rotation uses the queue minus part-time pharmacists, all unconstrained ('nm').
  // Each tier keeps its own rotation counter per bucket, so all rotate
  // continuously and independently.
  final partTimeIds = {for (final p in queue) if (p.partTime) p.id};
  const tierNames = ['cs', 'pt', 'nm'];
  final tiersByType = <String, Map<String, List<RosterEntry>>>{};
  for (final type in sortedTypes) {
    final all = type.hasCustomRoster
        ? type.roster.where((e) => validIds.contains(e.pharmacistId)).toList()
        : [
            for (final p in queue)
              if (!p.partTime) RosterEntry(pharmacistId: p.id),
          ];
    tiersByType[type.id] = {
      'cs': [for (final e in all) if (e.isConstrained) e],
      'pt': [
        for (final e in all)
          if (!e.isConstrained && partTimeIds.contains(e.pharmacistId)) e,
      ],
      'nm': [
        for (final e in all)
          if (!e.isConstrained && !partTimeIds.contains(e.pharmacistId)) e,
      ],
    };
  }

  // Per (type, bucket, tier) rotation pointer.
  final counters = <String, int>{};
  String counterKey(String typeId, DayBucket bucket, String tier) =>
      '$typeId|${bucket.name}|$tier';

  // Which tier a prior shift's pharmacist belongs to in [type] (for seeding).
  String tierOf(String typeId, String pharmacistId) {
    final tiers = tiersByType[typeId]!;
    for (final name in tierNames) {
      if (tiers[name]!.any((e) => e.pharmacistId == pharmacistId)) return name;
    }
    return 'nm';
  }

  // Seed each tier's counter from the latest prior shift of that type, in that
  // bucket, that one of the tier's members worked.
  for (final type in sortedTypes) {
    final tiers = tiersByType[type.id]!;
    final prior = priorTail.where((s) => s.typeId == type.id).toList()
      ..sort((a, b) => a.dateKey.compareTo(b.dateKey));
    final lastByBucketTier = <String, String>{}; // 'bucket|tier' → pharmacistId
    for (final s in prior) {
      final date = parseDateKey(s.dateKey);
      // A pinned weekday pick is not part of the rotation, so it must not seed
      // any counter for its bucket.
      if (type.weekdayPins.containsKey(date.weekday)) continue;
      final tier = tierOf(type.id, s.pharmacistId);
      final bucket =
          type.singleRotation ? DayBucket.all : bucketFor(date, holidayKeys);
      lastByBucketTier['${bucket.name}|$tier'] = s.pharmacistId;
    }
    lastByBucketTier.forEach((key, pharmacistId) {
      final parts = key.split('|'); // ['bucketName', 'tier']
      final list = tiers[parts[1]]!;
      final idx = list.indexWhere((e) => e.pharmacistId == pharmacistId);
      if (idx != -1) {
        counters['${type.id}|${parts[0]}|${parts[1]}'] =
            (idx + 1) % list.length;
      }
    });
  }

  // dateKey → assignments already on that day (so a linked type can find its
  // leader's pharmacist; seeded with any kept shifts).
  final byDay = <String, List<PlannedShift>>{};
  for (final s in keptShifts) {
    byDay.putIfAbsent(s.dateKey, () => []).add(s);
  }

  final result = <PlannedShift>[];
  for (
    var day = first;
    !day.isAfter(last);
    day = DateTime(day.year, day.month, day.day + 1)
  ) {
    final dateKey = dateKeyFor(day);
    final dayBucket = bucketFor(day, holidayKeys);
    for (final type in sortedTypes) {
      // A single-rotation type runs every day on one shared counter; others
      // follow the calendar bucket and their days/onHoliday rules.
      if (!type.singleRotation && !_typeRunsOn(type, day, dayBucket)) continue;
      if (keepSlots.contains('$dateKey|${type.id}')) continue;
      final bucket = type.singleRotation ? DayBucket.all : dayBucket;

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
      // explicit admin choice) and does NOT advance the bucket counter.
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

      // Try each tier in priority order: constrained entries first (they win on
      // their eligible days), then unconstrained part-timers, then the normal
      // rotation. Each tier scans forward from its own counter for the first
      // eligible participant; the first tier with one wins.
      final tiers = tiersByType[type.id]!;
      for (final tier in tierNames) {
        final list = tiers[tier]!;
        if (list.isEmpty) continue;

        final ckey = counterKey(type.id, bucket, tier);
        final ptr = (counters[ckey] ?? 0) % list.length;

        // Scan forward for the first eligible participant (no conflict checks).
        int? chosen;
        for (var i = 0; i < list.length; i++) {
          final idx = (ptr + i) % list.length;
          if (!list[idx].eligibleOn(day)) continue;
          chosen = idx;
          break;
        }
        if (chosen == null) continue; // nobody in this tier; try the next

        counters[ckey] = (chosen + 1) % list.length;
        emit(list[chosen].pharmacistId);
        break; // assigned: don't fall through to a lower-priority tier
      }
    }
  }
  return result;
}

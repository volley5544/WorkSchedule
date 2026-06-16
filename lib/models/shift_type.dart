import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

/// Which week of an alternating ("every other week") pattern a roster entry
/// runs on. Parity is measured against a fixed Monday epoch (see
/// [weekParityIndex]) so it stays stable and continuous across year boundaries.
enum WeekParity {
  /// Runs every week (no alternation).
  every,

  /// Runs on even-indexed weeks.
  weekA,

  /// Runs on odd-indexed weeks.
  weekB;

  static WeekParity fromName(String? name) => WeekParity.values.firstWhere(
        (p) => p.name == name,
        orElse: () => WeekParity.every,
      );

  String get label => switch (this) {
        WeekParity.every => 'Every week',
        WeekParity.weekA => 'Week A',
        WeekParity.weekB => 'Week B',
      };
}

/// Monday this app counts alternating weeks from (1 Jan 2024 is a Monday).
final DateTime _parityEpoch = DateTime(2024, 1, 1);

/// 0,1,2,… whole weeks since [_parityEpoch]. Even → Week A, odd → Week B.
/// Used by [RosterEntry.eligibleOn] to honour "every other week" rules.
int weekParityIndex(DateTime day) {
  final date = DateTime(day.year, day.month, day.day);
  return date.difference(_parityEpoch).inDays ~/ 7;
}

/// Which occurrence of [day]'s weekday this is within its month: 1 for the
/// first such weekday, … 5 for the fifth. E.g. a date that is the 5th Saturday
/// of its month returns 5. Used for "only the 5th Saturday" style rules.
int weekOfMonth(DateTime day) => ((day.day - 1) ~/ 7) + 1;

/// One participant in a shift type's custom rotation, with optional per-type
/// constraints. Powers 'ด' (a reshuffled order) and 'ณ' (a pharmacist who only
/// works the type on certain weekdays, optionally every other week).
class RosterEntry {
  const RosterEntry({
    required this.pharmacistId,
    this.weekdays = const [],
    this.parity = WeekParity.every,
    this.monthWeeks = const [],
  });

  final String pharmacistId;

  /// Weekday numbers (1 = Mon … 7 = Sun) this participant is eligible for in
  /// this type. Empty = every day the type runs.
  final List<int> weekdays;

  /// Alternating-week constraint; [WeekParity.every] = no alternation.
  final WeekParity parity;

  /// Which occurrences of the weekday within the month this participant is
  /// eligible for (1 = 1st … 5 = 5th, via [weekOfMonth]). Empty = all of them.
  /// E.g. `[5]` = only the 5th Saturday; `[1,2,3,4]` = every Saturday except a
  /// 5th one.
  final List<int> monthWeeks;

  /// Whether this participant may take the shift on [day] given their weekday,
  /// week-of-month and week-parity constraints.
  bool eligibleOn(DateTime day) {
    if (weekdays.isNotEmpty && !weekdays.contains(day.weekday)) return false;
    if (monthWeeks.isNotEmpty && !monthWeeks.contains(weekOfMonth(day))) {
      return false;
    }
    return switch (parity) {
      WeekParity.every => true,
      WeekParity.weekA => weekParityIndex(day).isEven,
      WeekParity.weekB => weekParityIndex(day).isOdd,
    };
  }

  /// True when the entry has any constraint beyond "every day, every week".
  bool get isConstrained =>
      weekdays.isNotEmpty || parity != WeekParity.every || monthWeeks.isNotEmpty;

  factory RosterEntry.fromMap(Map<String, dynamic> map) => RosterEntry(
        pharmacistId: map['pharmacistId'] as String? ?? '',
        weekdays: (map['weekdays'] as List?)?.cast<int>() ?? const [],
        parity: WeekParity.fromName(map['parity'] as String?),
        monthWeeks: (map['monthWeeks'] as List?)?.cast<int>() ?? const [],
      );

  Map<String, dynamic> toMap() => {
        'pharmacistId': pharmacistId,
        'weekdays': weekdays,
        'parity': parity.name,
        'monthWeeks': monthWeeks,
      };

  RosterEntry copyWith({
    List<int>? weekdays,
    WeekParity? parity,
    List<int>? monthWeeks,
  }) =>
      RosterEntry(
        pharmacistId: pharmacistId,
        weekdays: weekdays ?? this.weekdays,
        parity: parity ?? this.parity,
        monthWeeks: monthWeeks ?? this.monthWeeks,
      );
}

/// A configurable shift type (e.g. 'ช' 08:30–16:30), stored in the
/// `shiftTypes` collection. Admins manage these from the Shift types screen;
/// security rules restrict writes to admins.
class ShiftType {
  const ShiftType({
    required this.id,
    required this.label,
    required this.start,
    required this.end,
    required this.color,
    this.description = '',
    this.days = everyDay,
    this.onHoliday = false,
    this.roster = const [],
    this.weekdayPins = const {},
    this.followsTypeId = '',
    this.sortOrder = 0,
  });

  /// Weekday numbers matching [DateTime.weekday] (1 = Mon … 7 = Sun).
  static const everyDay = [1, 2, 3, 4, 5, 6, 7];

  final String id;

  /// Short code shown on the roster, e.g. 'ช'.
  final String label;

  /// Optional longer name, e.g. 'เวรเช้า'.
  final String description;

  /// Default working hours as `HH:mm`.
  final String start;
  final String end;
  final Color color;

  /// Weekdays this shift runs on ([DateTime.weekday] numbers); used by the
  /// auto-scheduler and shown in the config list. E.g. ช is Sat–Sun only
  /// because Mon–Fri 08:30–16:30 is the normal working day for everyone.
  ///
  /// On dates marked as holidays this list is ignored — a holiday is treated as
  /// a non-working day, so only types with [onHoliday] are scheduled then.
  final List<int> days;

  /// Whether this type is scheduled on holiday dates (which are treated like a
  /// non-working day, independent of [days]).
  final bool onHoliday;

  /// Optional custom rotation. Empty = rotate through the global pharmacist
  /// queue with no constraints (the default for ช/ย/บ).
  final List<RosterEntry> roster;

  /// Optional per-weekday pinned pharmacist: weekday number (1 = Mon … 7 = Sun)
  /// → pharmacist id. On any day this shift runs on a mapped weekday — a normal
  /// weekday, a weekend, or a holiday — that pharmacist is pinned instead of
  /// rotating; unmapped weekdays fall through to the normal rotation.
  final Map<int, String> weekdayPins;

  /// Id of another shift type this one is "linked" to: on any day the linked
  /// (leader) type is scheduled, this type is given the *same* pharmacist
  /// instead of rotating — e.g. บ follows ช on weekends/holidays so one person
  /// covers both. On days the leader doesn't run (ช skips weekdays), this type
  /// rotates normally. The leader must sort before this type.
  final String followsTypeId;

  final int sortOrder;

  static const _dayNames = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];

  /// Human-readable active days, e.g. 'Every day' or 'Sat, Sun'.
  String get daysLabel {
    if (days.length >= 7) return 'Every day';
    if (days.isEmpty) return 'No weekdays';
    final sorted = [...days]..sort();
    return sorted.map((d) => _dayNames[d - 1]).join(', ');
  }

  /// Whether the rotation is the reorderable per-type roster (vs the queue).
  bool get hasCustomRoster => roster.isNotEmpty;

  /// Whether any weekday has a pinned pharmacist.
  bool get hasWeekdayPins => weekdayPins.isNotEmpty;

  /// Whether this type follows another's pharmacist (see [followsTypeId]).
  bool get isLinked => followsTypeId.isNotEmpty;

  /// Placeholder for shifts whose type has been deleted from the config.
  factory ShiftType.unknown(String id) => ShiftType(
        id: id,
        label: id.isEmpty ? '?' : id,
        start: '',
        end: '',
        color: const Color(0xFF9E9E9E),
      );

  factory ShiftType.fromDoc(DocumentSnapshot<Map<String, dynamic>> doc) {
    final data = doc.data() ?? {};
    return ShiftType(
      id: doc.id,
      label: data['label'] as String? ?? '?',
      description: data['description'] as String? ?? '',
      start: data['start'] as String? ?? '08:00',
      end: data['end'] as String? ?? '16:00',
      color: Color(data['color'] as int? ?? 0xFF9E9E9E),
      days: (data['days'] as List?)?.cast<int>() ?? everyDay,
      onHoliday: data['onHoliday'] as bool? ?? false,
      roster:
          (data['roster'] as List?)
                  ?.map((e) => RosterEntry.fromMap((e as Map).cast()))
                  .toList() ??
              const [],
      // `holidayOverrides` is the former key (holiday-only); read it as a
      // fallback so existing config keeps working.
      weekdayPins:
          ((data['weekdayPins'] ?? data['holidayOverrides']) as Map?)?.map(
                (k, v) => MapEntry(int.parse(k.toString()), v as String),
              ) ??
              const {},
      followsTypeId: data['followsTypeId'] as String? ?? '',
      sortOrder: data['sortOrder'] as int? ?? 0,
    );
  }

  Map<String, dynamic> toMap() => {
        'label': label,
        'description': description,
        'start': start,
        'end': end,
        'color': color.toARGB32(),
        'days': days,
        'onHoliday': onHoliday,
        'roster': roster.map((e) => e.toMap()).toList(),
        'weekdayPins': {
          for (final e in weekdayPins.entries) e.key.toString(): e.value,
        },
        'followsTypeId': followsTypeId,
        'sortOrder': sortOrder,
      };

  ShiftType copyWith({
    String? label,
    String? description,
    String? start,
    String? end,
    Color? color,
    List<int>? days,
    bool? onHoliday,
    List<RosterEntry>? roster,
    Map<int, String>? weekdayPins,
    String? followsTypeId,
    int? sortOrder,
  }) =>
      ShiftType(
        id: id,
        label: label ?? this.label,
        description: description ?? this.description,
        start: start ?? this.start,
        end: end ?? this.end,
        color: color ?? this.color,
        days: days ?? this.days,
        onHoliday: onHoliday ?? this.onHoliday,
        roster: roster ?? this.roster,
        weekdayPins: weekdayPins ?? this.weekdayPins,
        followsTypeId: followsTypeId ?? this.followsTypeId,
        sortOrder: sortOrder ?? this.sortOrder,
      );

  /// The hospital's standard pharmacist shifts, used to seed an empty config.
  static const defaults = [
    // ช runs only on weekends: Mon–Fri 08:30–16:30 is the normal working
    // day for the whole group, not a scheduled shift. Holidays are non-working
    // days, so ช (and the evening/night shifts) cover them too.
    ShiftType(
        id: '',
        label: 'ช',
        description: 'เวรเช้า',
        start: '08:30',
        end: '16:30',
        color: Color(0xFFF59E0B),
        days: [DateTime.saturday, DateTime.sunday],
        onHoliday: true,
        sortOrder: 0),
    ShiftType(
        id: '',
        label: 'ย',
        description: 'เวรเย็น',
        start: '16:30',
        end: '20:30',
        color: Color(0xFF3B82F6),
        onHoliday: true,
        sortOrder: 1),
    ShiftType(
        id: '',
        label: 'บ',
        description: 'เวรบ่าย',
        start: '16:30',
        end: '23:30',
        color: Color(0xFF8B5CF6),
        onHoliday: true,
        sortOrder: 2),
    ShiftType(
        id: '',
        label: 'ด',
        description: 'เวรดึก',
        start: '23:30',
        end: '08:30',
        color: Color(0xFF14B8A6),
        onHoliday: true,
        sortOrder: 3),
  ];
}

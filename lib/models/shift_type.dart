import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

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
  final List<int> days;
  final int sortOrder;

  static const _dayNames = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];

  /// Human-readable active days, e.g. 'Every day' or 'Sat, Sun'.
  String get daysLabel {
    if (days.length >= 7) return 'Every day';
    final sorted = [...days]..sort();
    return sorted.map((d) => _dayNames[d - 1]).join(', ');
  }

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
        'sortOrder': sortOrder,
      };

  ShiftType copyWith({
    String? label,
    String? description,
    String? start,
    String? end,
    Color? color,
    List<int>? days,
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
        sortOrder: sortOrder ?? this.sortOrder,
      );

  /// The hospital's standard pharmacist shifts, used to seed an empty config.
  static const defaults = [
    // ช runs only on weekends: Mon–Fri 08:30–16:30 is the normal working
    // day for the whole group, not a scheduled shift.
    ShiftType(
        id: '',
        label: 'ช',
        description: 'เวรเช้า',
        start: '08:30',
        end: '16:30',
        color: Color(0xFFF59E0B),
        days: [DateTime.saturday, DateTime.sunday],
        sortOrder: 0),
    ShiftType(
        id: '',
        label: 'ย',
        description: 'เวรเย็น',
        start: '16:30',
        end: '20:30',
        color: Color(0xFF3B82F6),
        sortOrder: 1),
    ShiftType(
        id: '',
        label: 'บ',
        description: 'เวรบ่าย',
        start: '16:30',
        end: '23:30',
        color: Color(0xFF8B5CF6),
        sortOrder: 2),
    ShiftType(
        id: '',
        label: 'ด',
        description: 'เวรดึก',
        start: '23:30',
        end: '08:30',
        color: Color(0xFF14B8A6),
        sortOrder: 3),
  ];
}

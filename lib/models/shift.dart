import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

/// Standard hospital pharmacy shift types with default working hours.
enum ShiftType { morning, evening, night, onCall }

extension ShiftTypeX on ShiftType {
  String get label => switch (this) {
        ShiftType.morning => 'Morning',
        ShiftType.evening => 'Evening',
        ShiftType.night => 'Night',
        ShiftType.onCall => 'On-call',
      };

  String get defaultStart => switch (this) {
        ShiftType.morning => '08:00',
        ShiftType.evening => '16:00',
        ShiftType.night => '00:00',
        ShiftType.onCall => '08:00',
      };

  String get defaultEnd => switch (this) {
        ShiftType.morning => '16:00',
        ShiftType.evening => '00:00',
        ShiftType.night => '08:00',
        ShiftType.onCall => '08:00',
      };

  Color get color => switch (this) {
        ShiftType.morning => const Color(0xFFF59E0B),
        ShiftType.evening => const Color(0xFF3B82F6),
        ShiftType.night => const Color(0xFF8B5CF6),
        ShiftType.onCall => const Color(0xFF14B8A6),
      };

  static ShiftType fromString(String? value) => ShiftType.values.firstWhere(
        (t) => t.name == value,
        orElse: () => ShiftType.morning,
      );
}

class Shift {
  const Shift({
    required this.id,
    required this.dateKey,
    required this.type,
    required this.start,
    required this.end,
    required this.pharmacist,
    this.note = '',
    this.createdBy,
  });

  final String id;

  /// Day of the shift as `yyyy-MM-dd` (string keys sort & range-query cleanly).
  final String dateKey;
  final ShiftType type;

  /// Times as `HH:mm`.
  final String start;
  final String end;
  final String pharmacist;
  final String note;
  final String? createdBy;

  DateTime get date => DateTime.parse(dateKey);

  static String keyFor(DateTime day) =>
      '${day.year.toString().padLeft(4, '0')}-${day.month.toString().padLeft(2, '0')}-${day.day.toString().padLeft(2, '0')}';

  factory Shift.fromDoc(DocumentSnapshot<Map<String, dynamic>> doc) {
    final data = doc.data() ?? {};
    return Shift(
      id: doc.id,
      dateKey: data['dateKey'] as String? ?? '',
      type: ShiftTypeX.fromString(data['type'] as String?),
      start: data['start'] as String? ?? '',
      end: data['end'] as String? ?? '',
      pharmacist: data['pharmacist'] as String? ?? '',
      note: data['note'] as String? ?? '',
      createdBy: data['createdBy'] as String?,
    );
  }

  Map<String, dynamic> toMap() => {
        'dateKey': dateKey,
        'type': type.name,
        'start': start,
        'end': end,
        'pharmacist': pharmacist,
        'note': note,
        'createdBy': createdBy,
        'updatedAt': FieldValue.serverTimestamp(),
      };
}

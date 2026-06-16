import 'package:cloud_firestore/cloud_firestore.dart';

class Shift {
  const Shift({
    required this.id,
    required this.dateKey,
    required this.typeId,
    required this.start,
    required this.end,
    required this.pharmacist,
    this.pharmacistId = '',
    this.note = '',
    this.createdBy,
  });

  final String id;

  /// Day of the shift as `yyyy-MM-dd` (string keys sort & range-query cleanly).
  final String dateKey;

  /// Document id of the shift type in the `shiftTypes` collection. Resolved
  /// against the live config when rendering; deleted types fall back to
  /// [ShiftType.unknown].
  final String typeId;

  /// Times as `HH:mm`.
  final String start;
  final String end;

  /// Pharmacist display name, denormalized at save time so shifts stay
  /// readable even if the pharmacist is later removed from the config.
  final String pharmacist;

  /// Document id in the `pharmacists` collection ('' on legacy shifts
  /// created before the pharmacist config existed).
  final String pharmacistId;
  final String note;
  final String? createdBy;

  DateTime get date => DateTime.parse(dateKey);

  /// Minutes past midnight of [start], for ordering shifts by start time.
  /// Parses `HH:mm` robustly so unpadded/legacy values ('8:30') still sort
  /// correctly. Returns 0 when the time is missing/unparseable.
  int get startMinutes {
    final parts = start.split(':');
    return (int.tryParse(parts[0]) ?? 0) * 60 +
        (int.tryParse(parts.length > 1 ? parts[1] : '0') ?? 0);
  }

  /// Orders shifts by start time (earliest first), then by end time so two
  /// shifts that start together keep a stable order.
  static int byStartTime(Shift a, Shift b) {
    final byStart = a.startMinutes.compareTo(b.startMinutes);
    if (byStart != 0) return byStart;
    int endMin(Shift s) {
      final parts = s.end.split(':');
      return (int.tryParse(parts[0]) ?? 0) * 60 +
          (int.tryParse(parts.length > 1 ? parts[1] : '0') ?? 0);
    }

    return endMin(a).compareTo(endMin(b));
  }

  static String keyFor(DateTime day) =>
      '${day.year.toString().padLeft(4, '0')}-${day.month.toString().padLeft(2, '0')}-${day.day.toString().padLeft(2, '0')}';

  factory Shift.fromDoc(DocumentSnapshot<Map<String, dynamic>> doc) {
    final data = doc.data() ?? {};
    return Shift(
      id: doc.id,
      dateKey: data['dateKey'] as String? ?? '',
      typeId: data['type'] as String? ?? '',
      start: data['start'] as String? ?? '',
      end: data['end'] as String? ?? '',
      pharmacist: data['pharmacist'] as String? ?? '',
      pharmacistId: data['pharmacistId'] as String? ?? '',
      note: data['note'] as String? ?? '',
      createdBy: data['createdBy'] as String?,
    );
  }

  Map<String, dynamic> toMap() => {
        'dateKey': dateKey,
        'type': typeId,
        'start': start,
        'end': end,
        'pharmacist': pharmacist,
        'pharmacistId': pharmacistId,
        'note': note,
        'createdBy': createdBy,
        'updatedAt': FieldValue.serverTimestamp(),
      };
}

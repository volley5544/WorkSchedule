import 'package:cloud_firestore/cloud_firestore.dart';

import 'shift.dart';

/// A day the special after-hours clinic is closed
/// (วันหยุดคลินิกพิเศษเฉพาะทางนอกเวลาราชการ). Stored in the `holidays`
/// collection, one document per date (the doc id is the [dateKey]), managed by
/// admins. Shown on the calendar and roster so schedulers can see closed days
/// at a glance.
class Holiday {
  const Holiday({required this.id, required this.dateKey, this.name = ''});

  /// Document id; equals [dateKey] (one holiday per date).
  final String id;

  /// Day of the holiday as `yyyy-MM-dd`.
  final String dateKey;

  /// Reason / label, e.g. 'วันหยุดคลินิกพิเศษ'.
  final String name;

  DateTime get date => DateTime.parse(dateKey);

  factory Holiday.fromDoc(DocumentSnapshot<Map<String, dynamic>> doc) {
    final data = doc.data() ?? {};
    return Holiday(
      id: doc.id,
      dateKey: data['dateKey'] as String? ?? doc.id,
      name: data['name'] as String? ?? '',
    );
  }

  Map<String, dynamic> toMap() => {'dateKey': dateKey, 'name': name};

  /// The posted special-clinic closed days for B.E. 2569 (= 2026 CE), used to
  /// seed an empty config. Source: the hospital notice
  /// "วันหยุดคลินิกพิเศษเฉพาะทางนอกเวลาราชการ ปี 2569".
  static List<Holiday> get defaults2569 {
    const clinic = 'วันหยุดคลินิกพิเศษ';
    const cabinet = 'วันหยุดคลินิกพิเศษ (มติ ครม.)';
    const year = 2026; // B.E. 2569
    const groups = <({int month, List<int> days, String name})>[
      (month: 5, days: [2, 3, 4, 13, 30, 31], name: clinic),
      (month: 6, days: [1, 3], name: clinic),
      (month: 7, days: [28, 29, 30], name: clinic),
      (month: 8, days: [12], name: clinic),
      (month: 10, days: [12, 13, 14, 15, 16], name: cabinet),
      (month: 10, days: [23, 24, 25], name: clinic),
      (month: 12, days: [5, 6, 7, 10, 31], name: clinic),
    ];
    return [
      for (final g in groups)
        for (final d in g.days)
          Holiday(
            id: '',
            dateKey: Shift.keyFor(DateTime(year, g.month, d)),
            name: g.name,
          ),
    ];
  }
}

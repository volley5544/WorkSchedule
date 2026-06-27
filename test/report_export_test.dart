import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:work_schedule/models/pharmacist.dart';
import 'package:work_schedule/models/shift.dart';
import 'package:work_schedule/models/shift_type.dart';
import 'package:work_schedule/services/report_export.dart';

void main() {
  group('shiftHours', () {
    test('daytime shift', () {
      expect(ReportExport.shiftHours('08:30', '16:30'), 8.0);
    });

    test('overnight shift crossing midnight counts forward 24h', () {
      // ด 23:30 → 08:30 is 9 hours, not -15.
      expect(ReportExport.shiftHours('23:30', '08:30'), 9.0);
    });

    test('handles missing/blank times as zero-length', () {
      expect(ReportExport.shiftHours('', ''), 0.0);
    });
  });

  test('buildWorkbook produces a non-empty workbook from roster data', () {
    final month = DateTime(2026, 6);
    final types = [
      const ShiftType(
        id: 'ch',
        label: 'ช',
        start: '08:30',
        end: '16:30',
        color: Color(0xFFF59E0B),
        sortOrder: 0,
      ),
      const ShiftType(
        id: 'd',
        label: 'ด',
        start: '23:30',
        end: '08:30',
        color: Color(0xFF14B8A6),
        sortOrder: 1,
      ),
    ];
    final pharmacists = [
      const Pharmacist(id: 'p1', name: 'A', queue: 1),
      const Pharmacist(id: 'p2', name: 'B', queue: 2),
    ];
    final shiftsByDay = <String, List<Shift>>{
      '2026-06-06': [
        const Shift(
          id: 's1',
          dateKey: '2026-06-06',
          typeId: 'ch',
          start: '08:30',
          end: '16:30',
          pharmacist: 'A',
          pharmacistId: 'p1',
        ),
        const Shift(
          id: 's2',
          dateKey: '2026-06-06',
          typeId: 'd',
          start: '23:30',
          end: '08:30',
          pharmacist: 'B',
          pharmacistId: 'p2',
        ),
      ],
    };

    final bytes = ReportExport.buildWorkbook(
      months: [month],
      pharmacists: pharmacists,
      types: types,
      shiftsByDay: shiftsByDay,
      holidaysByDate: const {'2026-06-06': 'Test holiday'},
    );

    expect(bytes, isNotEmpty);
    // xlsx is a zip; the local-file header magic is 'PK'.
    expect(bytes[0], 0x50);
    expect(bytes[1], 0x4B);
  });

  test('buildWorkbook handles a multi-month range', () {
    final types = [
      const ShiftType(
        id: 'ch',
        label: 'ช',
        start: '08:30',
        end: '16:30',
        color: Color(0xFFF59E0B),
        sortOrder: 0,
      ),
    ];
    final pharmacists = [const Pharmacist(id: 'p1', name: 'A', queue: 1)];
    final shiftsByDay = <String, List<Shift>>{
      '2026-06-06': [
        const Shift(
          id: 's1',
          dateKey: '2026-06-06',
          typeId: 'ch',
          start: '08:30',
          end: '16:30',
          pharmacist: 'A',
          pharmacistId: 'p1',
        ),
      ],
      '2026-07-04': [
        const Shift(
          id: 's2',
          dateKey: '2026-07-04',
          typeId: 'ch',
          start: '08:30',
          end: '16:30',
          pharmacist: 'A',
          pharmacistId: 'p1',
        ),
      ],
    };

    final bytes = ReportExport.buildWorkbook(
      months: [DateTime(2026, 6), DateTime(2026, 7)],
      pharmacists: pharmacists,
      types: types,
      shiftsByDay: shiftsByDay,
    );

    expect(bytes, isNotEmpty);
    expect(bytes[0], 0x50);
    expect(bytes[1], 0x4B);
  });
}

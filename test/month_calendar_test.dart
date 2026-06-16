import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:work_schedule/models/shift.dart';
import 'package:work_schedule/models/shift_type.dart';
import 'package:work_schedule/widgets/month_calendar.dart';

void main() {
  Widget wrap(Widget child) => MaterialApp(
        home: Scaffold(body: SizedBox(height: 700, child: child)),
      );

  final june2026 = DateTime(2026, 6);
  const morning = ShiftType(
    id: 'morning',
    label: 'ช',
    start: '08:30',
    end: '16:30',
    color: Color(0xFFF59E0B),
  );
  const typesById = {'morning': morning};
  const shift = Shift(
    id: 's1',
    dateKey: '2026-06-15',
    typeId: 'morning',
    start: '08:30',
    end: '16:30',
    pharmacist: 'Alice',
  );

  testWidgets('renders every day of the month', (tester) async {
    await tester.pumpWidget(wrap(MonthCalendar(
      month: june2026,
      selectedDay: DateTime(2026, 6, 1),
      shiftsByDay: const {},
      typesById: typesById,
      onSelectDay: (_) {},
    )));
    expect(find.text('1'), findsOneWidget);
    expect(find.text('30'), findsOneWidget);
    expect(find.text('31'), findsNothing);
  });

  testWidgets('shows shift chip in the day cell on wide layout',
      (tester) async {
    await tester.pumpWidget(wrap(MonthCalendar(
      month: june2026,
      selectedDay: DateTime(2026, 6, 15),
      shiftsByDay: const {
        '2026-06-15': [shift]
      },
      typesById: typesById,
      onSelectDay: (_) {},
    )));
    expect(find.text('ช Alice'), findsOneWidget);
  });

  testWidgets('shift with a deleted type still renders, as unknown',
      (tester) async {
    await tester.pumpWidget(wrap(MonthCalendar(
      month: june2026,
      selectedDay: DateTime(2026, 6, 15),
      shiftsByDay: const {
        '2026-06-15': [shift]
      },
      typesById: const {},
      onSelectDay: (_) {},
    )));
    expect(find.text('morning Alice'), findsOneWidget);
  });

  testWidgets('tapping a day reports the selection', (tester) async {
    DateTime? selected;
    await tester.pumpWidget(wrap(MonthCalendar(
      month: june2026,
      selectedDay: DateTime(2026, 6, 1),
      shiftsByDay: const {},
      typesById: typesById,
      onSelectDay: (d) => selected = d,
    )));
    await tester.tap(find.text('20'));
    expect(selected, DateTime(2026, 6, 20));
  });

  test('Shift.keyFor pads single digits', () {
    expect(Shift.keyFor(DateTime(2026, 6, 5)), '2026-06-05');
  });

  test('Shift.byStartTime orders by start time, even unpadded', () {
    Shift at(String start, String end) => Shift(
          id: start,
          dateKey: '2026-06-06',
          typeId: 't',
          start: start,
          end: end,
          pharmacist: 'A',
        );
    final shifts = [
      at('23:30', '08:30'), // ด (night)
      at('8:30', '16:30'), // ช, unpadded
      at('16:30', '23:30'), // บ
      at('16:30', '20:30'), // ย, same start as บ but ends earlier
    ]..sort(Shift.byStartTime);
    expect(
      shifts.map((s) => '${s.start}-${s.end}').toList(),
      ['8:30-16:30', '16:30-20:30', '16:30-23:30', '23:30-08:30'],
    );
  });
}

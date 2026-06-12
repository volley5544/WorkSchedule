import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:work_schedule/models/shift.dart';
import 'package:work_schedule/widgets/month_calendar.dart';

void main() {
  Widget wrap(Widget child) => MaterialApp(
        home: Scaffold(body: SizedBox(height: 700, child: child)),
      );

  final june2026 = DateTime(2026, 6);
  const shift = Shift(
    id: 's1',
    dateKey: '2026-06-15',
    type: ShiftType.morning,
    start: '08:00',
    end: '16:00',
    pharmacist: 'Alice',
  );

  testWidgets('renders every day of the month', (tester) async {
    await tester.pumpWidget(wrap(MonthCalendar(
      month: june2026,
      selectedDay: DateTime(2026, 6, 1),
      shiftsByDay: const {},
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
      onSelectDay: (_) {},
    )));
    expect(find.text('08:00 Alice'), findsOneWidget);
  });

  testWidgets('tapping a day reports the selection', (tester) async {
    DateTime? selected;
    await tester.pumpWidget(wrap(MonthCalendar(
      month: june2026,
      selectedDay: DateTime(2026, 6, 1),
      shiftsByDay: const {},
      onSelectDay: (d) => selected = d,
    )));
    await tester.tap(find.text('20'));
    expect(selected, DateTime(2026, 6, 20));
  });

  test('Shift.keyFor pads single digits', () {
    expect(Shift.keyFor(DateTime(2026, 6, 5)), '2026-06-05');
  });
}

import 'package:flutter/material.dart';

import '../models/shift.dart';

/// Custom month-grid calendar built for shift rosters.
///
/// Wide screens (`compact == false`) render shift chips directly inside each
/// day cell; narrow screens render small colored dots and rely on a separate
/// day-detail panel for the full list.
class MonthCalendar extends StatelessWidget {
  const MonthCalendar({
    super.key,
    required this.month,
    required this.selectedDay,
    required this.shiftsByDay,
    required this.onSelectDay,
    this.onDoubleTapDay,
    this.compact = false,
  });

  final DateTime month;
  final DateTime selectedDay;
  final Map<String, List<Shift>> shiftsByDay;
  final ValueChanged<DateTime> onSelectDay;
  final ValueChanged<DateTime>? onDoubleTapDay;
  final bool compact;

  static const _weekdays = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];

  @override
  Widget build(BuildContext context) {
    final first = DateTime(month.year, month.month, 1);
    final daysInMonth = DateTime(month.year, month.month + 1, 0).day;
    final leadingBlanks = first.weekday - 1; // Monday-first grid
    final totalCells = leadingBlanks + daysInMonth;
    final rows = (totalCells / 7).ceil();

    return Column(
      children: [
        _WeekdayHeader(labels: _weekdays, compact: compact),
        for (var row = 0; row < rows; row++)
          Expanded(
            child: Row(
              children: [
                for (var col = 0; col < 7; col++)
                  Expanded(
                    child: _buildCell(context, row * 7 + col - leadingBlanks),
                  ),
              ],
            ),
          ),
      ],
    );
  }

  Widget _buildCell(BuildContext context, int dayIndex) {
    final daysInMonth = DateTime(month.year, month.month + 1, 0).day;
    if (dayIndex < 0 || dayIndex >= daysInMonth) {
      return const SizedBox.shrink();
    }
    final day = DateTime(month.year, month.month, dayIndex + 1);
    final shifts = shiftsByDay[Shift.keyFor(day)] ?? const <Shift>[];
    return _DayCell(
      day: day,
      shifts: shifts,
      isSelected: DateUtils.isSameDay(day, selectedDay),
      isToday: DateUtils.isSameDay(day, DateTime.now()),
      isWeekend: day.weekday >= DateTime.saturday,
      compact: compact,
      onTap: () => onSelectDay(day),
      onDoubleTap:
          onDoubleTapDay == null ? null : () => onDoubleTapDay!(day),
    );
  }
}

class _WeekdayHeader extends StatelessWidget {
  const _WeekdayHeader({required this.labels, required this.compact});

  final List<String> labels;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final style = Theme.of(context).textTheme.labelMedium?.copyWith(
          color: Theme.of(context).colorScheme.onSurfaceVariant,
          fontWeight: FontWeight.w600,
        );
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: [
          for (final label in labels)
            Expanded(
              child: Center(
                child: Text(compact ? label.substring(0, 1) : label,
                    style: style),
              ),
            ),
        ],
      ),
    );
  }
}

class _DayCell extends StatelessWidget {
  const _DayCell({
    required this.day,
    required this.shifts,
    required this.isSelected,
    required this.isToday,
    required this.isWeekend,
    required this.compact,
    required this.onTap,
    this.onDoubleTap,
  });

  final DateTime day;
  final List<Shift> shifts;
  final bool isSelected;
  final bool isToday;
  final bool isWeekend;
  final bool compact;
  final VoidCallback onTap;
  final VoidCallback? onDoubleTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.all(1.5),
      child: Material(
        color: isSelected
            ? scheme.primaryContainer.withValues(alpha: 0.6)
            : isWeekend
                ? scheme.surfaceContainerHighest.withValues(alpha: 0.4)
                : scheme.surface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(8),
          side: BorderSide(
            color: isSelected
                ? scheme.primary
                : scheme.outlineVariant.withValues(alpha: 0.5),
            width: isSelected ? 1.5 : 1,
          ),
        ),
        child: InkWell(
          borderRadius: BorderRadius.circular(8),
          onTap: onTap,
          onDoubleTap: onDoubleTap,
          child: Padding(
            padding: EdgeInsets.all(compact ? 2 : 4),
            child: compact ? _buildCompact(scheme) : _buildFull(context),
          ),
        ),
      ),
    );
  }

  Widget _dayNumber(ColorScheme scheme) {
    return Container(
      width: 24,
      height: 24,
      alignment: Alignment.center,
      decoration: isToday
          ? BoxDecoration(color: scheme.primary, shape: BoxShape.circle)
          : null,
      child: Text(
        '${day.day}',
        style: TextStyle(
          fontSize: 12,
          fontWeight: isToday ? FontWeight.bold : FontWeight.w500,
          color: isToday ? scheme.onPrimary : scheme.onSurface,
        ),
      ),
    );
  }

  Widget _buildCompact(ColorScheme scheme) {
    final types = shifts.map((s) => s.type).toSet().toList();
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        _dayNumber(scheme),
        const SizedBox(height: 2),
        SizedBox(
          height: 6,
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              for (final type in types.take(4))
                Container(
                  width: 6,
                  height: 6,
                  margin: const EdgeInsets.symmetric(horizontal: 1),
                  decoration: BoxDecoration(
                    color: type.color,
                    shape: BoxShape.circle,
                  ),
                ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildFull(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return LayoutBuilder(builder: (context, constraints) {
      // Each chip needs ~18px; reserve 26px for the day number row. When not
      // everything fits, the last slot is used by the "+n more" label instead.
      final capacity = ((constraints.maxHeight - 26) / 18).floor();
      final shown = shifts.length <= capacity
          ? shifts.length
          : (capacity - 1).clamp(0, shifts.length);
      final overflow = shifts.length - shown;
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _dayNumber(scheme),
          const SizedBox(height: 2),
          for (final shift in shifts.take(shown)) _ShiftChip(shift: shift),
          if (overflow > 0)
            Padding(
              padding: const EdgeInsets.only(left: 2, top: 1),
              child: Text(
                '+$overflow more',
                style: TextStyle(
                  fontSize: 10,
                  color: scheme.onSurfaceVariant,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
        ],
      );
    });
  }
}

class _ShiftChip extends StatelessWidget {
  const _ShiftChip({required this.shift});

  final Shift shift;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 2),
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
      width: double.infinity,
      decoration: BoxDecoration(
        color: shift.type.color.withValues(alpha: 0.18),
        borderRadius: BorderRadius.circular(4),
        border: Border(
          left: BorderSide(color: shift.type.color, width: 3),
        ),
      ),
      child: Text(
        '${shift.start} ${shift.pharmacist}',
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: const TextStyle(fontSize: 10.5, fontWeight: FontWeight.w500),
      ),
    );
  }
}

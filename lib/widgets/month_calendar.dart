import 'package:flutter/material.dart';

import '../l10n/app_text.dart';
import '../models/shift.dart';
import '../models/shift_type.dart';

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
    required this.typesById,
    required this.onSelectDay,
    this.holidaysByDate = const {},
    this.onDoubleTapDay,
    this.compact = false,
    this.codeOnly = false,
  });

  final DateTime month;
  final DateTime selectedDay;
  final Map<String, List<Shift>> shiftsByDay;
  final Map<String, ShiftType> typesById;

  /// Clinic holidays as dateKey → name; marked days are shaded red.
  final Map<String, String> holidaysByDate;
  final ValueChanged<DateTime> onSelectDay;
  final ValueChanged<DateTime>? onDoubleTapDay;
  final bool compact;

  /// Render chips with just the shift code, large and centered — used by
  /// the "My shifts" view where every shift belongs to the same person.
  final bool codeOnly;

  @override
  Widget build(BuildContext context) {
    final first = DateTime(month.year, month.month, 1);
    final daysInMonth = DateTime(month.year, month.month + 1, 0).day;
    final leadingBlanks = first.weekday - 1; // Monday-first grid
    final totalCells = leadingBlanks + daysInMonth;
    final rows = (totalCells / 7).ceil();

    final t = AppText.of(context);
    return Column(
      children: [
        _WeekdayHeader(
          labels: compact ? t.weekdaysMin : t.weekdaysShort,
          compact: compact,
        ),
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
      typesById: typesById,
      isSelected: DateUtils.isSameDay(day, selectedDay),
      isToday: DateUtils.isSameDay(day, DateTime.now()),
      isWeekend: day.weekday >= DateTime.saturday,
      holidayName: holidaysByDate[Shift.keyFor(day)],
      compact: compact,
      codeOnly: codeOnly,
      onTap: () => onSelectDay(day),
      onDoubleTap: onDoubleTapDay == null ? null : () => onDoubleTapDay!(day),
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
                child: Text(label, style: style),
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
    required this.typesById,
    required this.isSelected,
    required this.isToday,
    required this.isWeekend,
    required this.compact,
    required this.codeOnly,
    required this.onTap,
    this.holidayName,
    this.onDoubleTap,
  });

  final DateTime day;
  final List<Shift> shifts;
  final Map<String, ShiftType> typesById;
  final bool isSelected;
  final bool isToday;
  final bool isWeekend;

  /// Non-null when the day is a clinic holiday; the value is its name.
  final String? holidayName;
  final bool compact;
  final bool codeOnly;
  final VoidCallback onTap;
  final VoidCallback? onDoubleTap;

  bool get isHoliday => holidayName != null;

  ShiftType _typeOf(Shift shift) =>
      typesById[shift.typeId] ?? ShiftType.unknown(shift.typeId);

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    Widget cell = Material(
      color: isSelected
          ? scheme.primaryContainer.withValues(alpha: 0.6)
          : isHoliday
          ? scheme.errorContainer.withValues(alpha: 0.4)
          : isWeekend
          ? scheme.surfaceContainerHighest.withValues(alpha: 0.4)
          : scheme.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(8),
        side: BorderSide(
          color: isSelected
              ? scheme.primary
              : isHoliday
              ? scheme.error.withValues(alpha: 0.4)
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
    );
    if (isHoliday && holidayName!.isNotEmpty) {
      cell = Tooltip(message: holidayName, child: cell);
    }
    return Padding(padding: const EdgeInsets.all(1.5), child: cell);
  }

  Widget _dayNumber(ColorScheme scheme) {
    final number = Container(
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
          color: isToday
              ? scheme.onPrimary
              : isHoliday
              ? scheme.error
              : scheme.onSurface,
        ),
      ),
    );
    if (!isHoliday) return number;
    // A small red dot flags holidays even where the red tint is subtle.
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        number,
        const SizedBox(width: 3),
        Container(
          width: 6,
          height: 6,
          decoration: BoxDecoration(
            color: scheme.error,
            shape: BoxShape.circle,
          ),
        ),
      ],
    );
  }

  Widget _buildCompact(ColorScheme scheme) {
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      mainAxisSize: MainAxisSize.min,
      children: [
        _dayNumber(scheme),
        const SizedBox(height: 2),
        // "My shifts" shows the actual shift codes so a pharmacist can read
        // their roster on a phone; the busy "By day" view keeps colored dots.
        codeOnly ? _buildCompactCodes() : _buildCompactDots(),
      ],
    );
  }

  Widget _buildCompactDots() {
    final colors = shifts.map((s) => _typeOf(s).color).toSet().toList();
    return SizedBox(
      height: 6,
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          for (final color in colors.take(4))
            Container(
              width: 6,
              height: 6,
              margin: const EdgeInsets.symmetric(horizontal: 1),
              decoration: BoxDecoration(color: color, shape: BoxShape.circle),
            ),
        ],
      ),
    );
  }

  /// Fixed height reserved for the compact codes row so that days without a
  /// shift occupy exactly as much space as days with one — otherwise the
  /// vertically-centered column changes height and the day numbers visibly
  /// jump around as you scan the month.
  static const _compactCodesHeight = 18.0;

  Widget _buildCompactCodes() {
    // De-duplicate by type but keep schedule order.
    final seen = <String>{};
    final types = <ShiftType>[];
    for (final shift in shifts) {
      final type = _typeOf(shift);
      if (seen.add(type.id)) types.add(type);
    }
    if (types.isEmpty) return const SizedBox(height: _compactCodesHeight);
    return SizedBox(
      height: _compactCodesHeight,
      child: Wrap(
        alignment: WrapAlignment.center,
        spacing: 2,
        children: [
          for (final type in types.take(2))
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
              decoration: BoxDecoration(
                color: type.color.withValues(alpha: 0.18),
                borderRadius: BorderRadius.circular(4),
              ),
              child: Text(
                type.label,
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.bold,
                  color: type.color,
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildFull(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return LayoutBuilder(
      builder: (context, constraints) {
        // Reserve 26px for the day number row. When not everything fits, the
        // last slot is used by the "+n more" label instead.
        final chipHeight = codeOnly ? 24 : 18;
        final capacity = ((constraints.maxHeight - 26) / chipHeight).floor();
        final shown = shifts.length <= capacity
            ? shifts.length
            : (capacity - 1).clamp(0, shifts.length);
        final overflow = shifts.length - shown;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _dayNumber(scheme),
            const SizedBox(height: 2),
            for (final shift in shifts.take(shown))
              _ShiftChip(
                shift: shift,
                type: _typeOf(shift),
                codeOnly: codeOnly,
              ),
            if (overflow > 0)
              Padding(
                padding: const EdgeInsets.only(left: 2, top: 1),
                child: Text(
                  AppText.of(context).overflowMore(overflow),
                  style: TextStyle(
                    fontSize: 10,
                    color: scheme.onSurfaceVariant,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
          ],
        );
      },
    );
  }
}

class _ShiftChip extends StatelessWidget {
  const _ShiftChip({
    required this.shift,
    required this.type,
    this.codeOnly = false,
  });

  final Shift shift;
  final ShiftType type;
  final bool codeOnly;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 2),
      padding: EdgeInsets.symmetric(horizontal: 4, vertical: codeOnly ? 2 : 1),
      width: double.infinity,
      decoration: BoxDecoration(
        color: type.color.withValues(alpha: 0.18),
        borderRadius: BorderRadius.circular(4),
        border: codeOnly
            ? null
            : Border(left: BorderSide(color: type.color, width: 3)),
      ),
      child: Text(
        codeOnly ? type.label : '${type.label} ${shift.pharmacist}',
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        textAlign: codeOnly ? TextAlign.center : TextAlign.start,
        style: codeOnly
            ? TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.bold,
                color: type.color,
              )
            : const TextStyle(fontSize: 10.5, fontWeight: FontWeight.w500),
      ),
    );
  }
}

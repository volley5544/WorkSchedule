import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../l10n/app_text.dart';
import '../models/pharmacist.dart';
import '../models/shift.dart';
import '../models/shift_type.dart';

const _rowHeight = 54.0;
const _headerHeight = 44.0;
const _nameColWidth = 168.0;
const _dayColWidth = 50.0;

/// Month roster matrix: one row per pharmacist, one column per day, shift
/// type codes in the cells — a modern take on the classic printed roster.
class RosterTable extends StatefulWidget {
  const RosterTable({
    super.key,
    required this.month,
    required this.pharmacists,
    required this.shiftsByDay,
    required this.typesById,
    this.holidaysByDate = const {},
    this.onTapCell,
  });

  final DateTime month;
  final List<Pharmacist> pharmacists;
  final Map<String, List<Shift>> shiftsByDay;
  final Map<String, ShiftType> typesById;

  /// Clinic holidays as dateKey → name; marked columns are shaded red.
  final Map<String, String> holidaysByDate;

  /// Called with the pharmacist, the day, and that cell's shifts.
  final void Function(Pharmacist, DateTime, List<Shift>)? onTapCell;

  @override
  State<RosterTable> createState() => _RosterTableState();
}

class _RosterTableState extends State<RosterTable> {
  final _hScroll = ScrollController();

  /// Row highlighted by tapping a pharmacist's name; tap again to clear.
  String? _focusedPharmacistId;

  @override
  void dispose() {
    _hScroll.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final t = AppText.of(context);
    final month = widget.month;
    // Rows follow the table display order (showOrder), falling back to queue.
    final pharmacists = [...widget.pharmacists]..sort(Pharmacist.byShowOrder);
    final shiftsByDay = widget.shiftsByDay;
    final typesById = widget.typesById;
    final holidaysByDate = widget.holidaysByDate;
    final onTapCell = widget.onTapCell;
    final daysInMonth = DateTime(month.year, month.month + 1, 0).day;
    final today = DateTime.now();

    // Index shifts by (pharmacistId, dateKey) for cell lookup, each cell's
    // shifts ordered by start time (earliest first).
    final byCell = <String, List<Shift>>{};
    for (final dayShifts in shiftsByDay.values) {
      for (final shift in dayShifts) {
        byCell
            .putIfAbsent('${shift.pharmacistId}|${shift.dateKey}', () => [])
            .add(shift);
      }
    }
    for (final cellShifts in byCell.values) {
      cellShifts.sort(Shift.byStartTime);
    }

    if (pharmacists.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text(
            t.noPharmacistsConfigured,
            textAlign: TextAlign.center,
            style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ),
      );
    }

    return Card(
      margin: const EdgeInsets.all(8),
      clipBehavior: Clip.antiAlias,
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: theme.colorScheme.outlineVariant),
      ),
      child: SingleChildScrollView(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Pinned name column.
            SizedBox(
              width: _nameColWidth,
              child: Column(
                children: [
                  _HeaderCell(
                    width: _nameColWidth,
                    child: Text(
                      t.pharmacistColumn,
                      style: theme.textTheme.labelLarge?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                  for (final pharmacist in pharmacists)
                    _NameCell(
                      pharmacist: pharmacist,
                      focused: pharmacist.id == _focusedPharmacistId,
                      onTap: () => setState(
                        () => _focusedPharmacistId =
                            _focusedPharmacistId == pharmacist.id
                            ? null
                            : pharmacist.id,
                      ),
                    ),
                ],
              ),
            ),
            // Scrollable day grid. Mouse drag is enabled so the table can be
            // panned left–right on desktop/web, with an always-visible
            // scrollbar as the affordance.
            Expanded(
              child: ScrollConfiguration(
                behavior: ScrollConfiguration.of(context).copyWith(
                  dragDevices: {
                    PointerDeviceKind.touch,
                    PointerDeviceKind.mouse,
                    PointerDeviceKind.trackpad,
                    PointerDeviceKind.stylus,
                  },
                ),
                child: Scrollbar(
                  controller: _hScroll,
                  thumbVisibility: true,
                  child: SingleChildScrollView(
                    controller: _hScroll,
                    scrollDirection: Axis.horizontal,
                    padding: const EdgeInsets.only(bottom: 10),
                    child: Column(
                      children: [
                        Row(
                          children: [
                            for (var d = 1; d <= daysInMonth; d++)
                              _DayHeaderCell(
                                day: DateTime(month.year, month.month, d),
                                isToday: DateUtils.isSameDay(
                                  DateTime(month.year, month.month, d),
                                  today,
                                ),
                                holidayName:
                                    holidaysByDate[Shift.keyFor(
                                      DateTime(month.year, month.month, d),
                                    )],
                              ),
                          ],
                        ),
                        for (final pharmacist in pharmacists)
                          Row(
                            children: [
                              for (var d = 1; d <= daysInMonth; d++)
                                _ShiftCell(
                                  day: DateTime(month.year, month.month, d),
                                  shifts:
                                      byCell['${pharmacist.id}|${Shift.keyFor(DateTime(month.year, month.month, d))}'] ??
                                      const [],
                                  typesById: typesById,
                                  isToday: DateUtils.isSameDay(
                                    DateTime(month.year, month.month, d),
                                    today,
                                  ),
                                  isHoliday: holidaysByDate.containsKey(
                                    Shift.keyFor(
                                      DateTime(month.year, month.month, d),
                                    ),
                                  ),
                                  focused:
                                      pharmacist.id == _focusedPharmacistId,
                                  onTap: onTapCell == null
                                      ? null
                                      : (shifts) => onTapCell(
                                          pharmacist,
                                          DateTime(month.year, month.month, d),
                                          shifts,
                                        ),
                                ),
                            ],
                          ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _HeaderCell extends StatelessWidget {
  const _HeaderCell({required this.width, required this.child});

  final double width;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      width: width,
      height: _headerHeight,
      alignment: Alignment.centerLeft,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest,
        border: Border(
          bottom: BorderSide(color: theme.colorScheme.outlineVariant),
        ),
      ),
      child: child,
    );
  }
}

class _NameCell extends StatelessWidget {
  const _NameCell({
    required this.pharmacist,
    required this.focused,
    required this.onTap,
  });

  final Pharmacist pharmacist;
  final bool focused;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return InkWell(
      onTap: onTap,
      child: Container(
        height: _rowHeight,
        padding: const EdgeInsets.symmetric(horizontal: 8),
        decoration: BoxDecoration(
          color: focused
              ? theme.colorScheme.primaryContainer.withValues(alpha: 0.55)
              : null,
          border: Border(
            left: focused
                ? BorderSide(color: theme.colorScheme.primary, width: 3)
                : BorderSide.none,
            bottom: BorderSide(
              color: theme.colorScheme.outlineVariant.withValues(alpha: 0.5),
            ),
          ),
        ),
        child: Row(
          children: [
            CircleAvatar(
              radius: 11,
              backgroundColor: theme.colorScheme.secondaryContainer,
              child: Text(
                '${pharmacist.queue}',
                style: TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.bold,
                  color: theme.colorScheme.onSecondaryContainer,
                ),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    pharmacist.fullName,
                    maxLines: pharmacist.nickname.isEmpty ? 2 : 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  if (pharmacist.nickname.isNotEmpty)
                    Text(
                      pharmacist.nickname,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 10,
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _DayHeaderCell extends StatelessWidget {
  const _DayHeaderCell({
    required this.day,
    required this.isToday,
    this.holidayName,
  });

  final DateTime day;
  final bool isToday;

  /// Non-null when the day is a clinic holiday; the value is its name.
  final String? holidayName;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isWeekend = day.weekday >= DateTime.saturday;
    final isHoliday = holidayName != null;
    final cell = Container(
      width: _dayColWidth,
      height: _headerHeight,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: isToday
            ? theme.colorScheme.primaryContainer
            : isHoliday
            ? theme.colorScheme.errorContainer.withValues(alpha: 0.55)
            : isWeekend
            ? theme.colorScheme.surfaceContainerHighest
            : theme.colorScheme.surfaceContainerHigh,
        border: Border(
          bottom: BorderSide(color: theme.colorScheme.outlineVariant),
        ),
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text(
            DateFormat('E').format(day).substring(0, 1),
            style: TextStyle(
              fontSize: 9,
              color: theme.colorScheme.onSurfaceVariant,
              fontWeight: FontWeight.w600,
            ),
          ),
          Text(
            '${day.day}',
            style: TextStyle(
              fontSize: 12,
              fontWeight: isToday ? FontWeight.bold : FontWeight.w600,
              color: isToday
                  ? theme.colorScheme.onPrimaryContainer
                  : isHoliday
                  ? theme.colorScheme.error
                  : theme.colorScheme.onSurface,
            ),
          ),
        ],
      ),
    );
    if (isHoliday && holidayName!.isNotEmpty) {
      return Tooltip(message: holidayName, child: cell);
    }
    return cell;
  }
}

class _ShiftCell extends StatelessWidget {
  const _ShiftCell({
    required this.day,
    required this.shifts,
    required this.typesById,
    required this.isToday,
    required this.focused,
    this.isHoliday = false,
    this.onTap,
  });

  final DateTime day;
  final List<Shift> shifts;
  final Map<String, ShiftType> typesById;
  final bool isToday;
  final bool focused;
  final bool isHoliday;
  final void Function(List<Shift>)? onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isWeekend = day.weekday >= DateTime.saturday;
    final base = isToday
        ? theme.colorScheme.primaryContainer.withValues(alpha: 0.25)
        : isHoliday
        ? theme.colorScheme.errorContainer.withValues(alpha: 0.3)
        : isWeekend
        ? theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.45)
        : null;
    // Focused rows get a primary tint layered over the day/weekend shading.
    final background = focused
        ? Color.alphaBlend(
            theme.colorScheme.primary.withValues(alpha: 0.12),
            base ?? theme.colorScheme.surface,
          )
        : base;
    return InkWell(
      onTap: onTap == null ? null : () => onTap!(shifts),
      child: Container(
        width: _dayColWidth,
        height: _rowHeight,
        alignment: Alignment.center,
        padding: const EdgeInsets.all(2),
        decoration: BoxDecoration(
          color: background,
          border: Border(
            bottom: BorderSide(
              color: theme.colorScheme.outlineVariant.withValues(alpha: 0.5),
            ),
            right: BorderSide(
              color: theme.colorScheme.outlineVariant.withValues(alpha: 0.25),
            ),
          ),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            for (final shift in shifts.take(2))
              _CodeChip(
                type:
                    typesById[shift.typeId] ?? ShiftType.unknown(shift.typeId),
              ),
            if (shifts.length > 2)
              Text(
                '+${shifts.length - 2}',
                style: TextStyle(
                  fontSize: 9,
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _CodeChip extends StatelessWidget {
  const _CodeChip({required this.type});

  final ShiftType type;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.symmetric(vertical: 1),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 1),
      decoration: BoxDecoration(
        color: type.color.withValues(alpha: 0.18),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        type.label,
        style: TextStyle(
          fontSize: 15,
          fontWeight: FontWeight.bold,
          color: type.color,
        ),
      ),
    );
  }
}

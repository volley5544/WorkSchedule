import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../models/shift.dart';

/// Lists every shift for the selected day; editors can tap a shift to edit it.
class DayShiftsPanel extends StatelessWidget {
  const DayShiftsPanel({
    super.key,
    required this.day,
    required this.shifts,
    required this.canEdit,
    this.onEditShift,
    this.onAddShift,
  });

  final DateTime day;
  final List<Shift> shifts;
  final bool canEdit;
  final ValueChanged<Shift>? onEditShift;
  final VoidCallback? onAddShift;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 8, 4),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  DateFormat('EEEE, d MMMM yyyy').format(day),
                  style: theme.textTheme.titleMedium
                      ?.copyWith(fontWeight: FontWeight.w600),
                ),
              ),
              if (canEdit && onAddShift != null)
                IconButton(
                  tooltip: 'Add shift',
                  icon: const Icon(Icons.add_circle_outline),
                  onPressed: onAddShift,
                ),
            ],
          ),
        ),
        if (shifts.isEmpty)
          Padding(
            padding: const EdgeInsets.all(16),
            child: Text(
              'No shifts scheduled.',
              style: theme.textTheme.bodyMedium
                  ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
            ),
          )
        else
          Expanded(
            child: ListView.builder(
              padding: const EdgeInsets.symmetric(horizontal: 8),
              itemCount: shifts.length,
              itemBuilder: (context, i) => _ShiftTile(
                shift: shifts[i],
                onTap: canEdit && onEditShift != null
                    ? () => onEditShift!(shifts[i])
                    : null,
              ),
            ),
          ),
      ],
    );
  }
}

class _ShiftTile extends StatelessWidget {
  const _ShiftTile({required this.shift, this.onTap});

  final Shift shift;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      elevation: 0,
      margin: const EdgeInsets.symmetric(vertical: 3),
      color: shift.type.color.withValues(alpha: 0.10),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(10),
        side: BorderSide(color: shift.type.color.withValues(alpha: 0.4)),
      ),
      child: ListTile(
        dense: true,
        onTap: onTap,
        leading: CircleAvatar(
          radius: 16,
          backgroundColor: shift.type.color,
          child: Text(
            shift.pharmacist.isEmpty
                ? '?'
                : shift.pharmacist.characters.first.toUpperCase(),
            style: const TextStyle(
                color: Colors.white, fontWeight: FontWeight.bold),
          ),
        ),
        title: Text(
          shift.pharmacist,
          style: const TextStyle(fontWeight: FontWeight.w600),
        ),
        subtitle: Text(
          '${shift.type.label} · ${shift.start}–${shift.end}'
          '${shift.note.isEmpty ? '' : '\n${shift.note}'}',
          style: theme.textTheme.bodySmall,
        ),
        trailing: onTap == null ? null : const Icon(Icons.edit_outlined, size: 18),
      ),
    );
  }
}

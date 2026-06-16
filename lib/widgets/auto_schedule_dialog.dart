import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../l10n/app_text.dart';

/// What the user picked in the auto-schedule dialog.
typedef AutoScheduleRequest = ({
  DateTime startMonth,
  int months,
  bool replaceExisting,
});

/// Asks for a start month and how many months to fill. Returns null if
/// cancelled.
Future<AutoScheduleRequest?> showAutoScheduleDialog(BuildContext context) {
  return showDialog<AutoScheduleRequest>(
    context: context,
    builder: (_) => const _AutoScheduleDialog(),
  );
}

class _AutoScheduleDialog extends StatefulWidget {
  const _AutoScheduleDialog();

  @override
  State<_AutoScheduleDialog> createState() => _AutoScheduleDialogState();
}

class _AutoScheduleDialogState extends State<_AutoScheduleDialog> {
  // Default to the month after the current one.
  late DateTime _startMonth =
      DateTime(DateTime.now().year, DateTime.now().month + 1);
  int _months = 3;
  bool _replaceExisting = false;

  void _shiftStart(int delta) {
    setState(() =>
        _startMonth = DateTime(_startMonth.year, _startMonth.month + delta));
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final t = AppText.of(context);
    return AlertDialog(
      title: Text(t.autoSchedule),
      content: SizedBox(
        width: 360,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(t.startMonth, style: theme.textTheme.labelLarge),
            Row(
              children: [
                IconButton(
                  tooltip: t.previousMonth,
                  icon: const Icon(Icons.chevron_left),
                  onPressed: () => _shiftStart(-1),
                ),
                Expanded(
                  child: Center(
                    child: Text(
                      DateFormat('MMMM yyyy').format(_startMonth),
                      style: theme.textTheme.titleMedium
                          ?.copyWith(fontWeight: FontWeight.w600),
                    ),
                  ),
                ),
                IconButton(
                  tooltip: t.nextMonth,
                  icon: const Icon(Icons.chevron_right),
                  onPressed: () => _shiftStart(1),
                ),
              ],
            ),
            const SizedBox(height: 12),
            DropdownButtonFormField<int>(
              initialValue: _months,
              decoration: InputDecoration(
                labelText: t.monthsToFill,
                border: const OutlineInputBorder(),
              ),
              items: [
                for (var m = 1; m <= 6; m++)
                  DropdownMenuItem(value: m, child: Text(t.monthCount(m))),
              ],
              onChanged: (m) {
                if (m != null) setState(() => _months = m);
              },
            ),
            const SizedBox(height: 8),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: Text(t.regenerateExisting),
              subtitle: Text(
                _replaceExisting ? t.regenerateOn : t.regenerateOff,
                style: theme.textTheme.bodySmall,
              ),
              value: _replaceExisting,
              onChanged: (v) => setState(() => _replaceExisting = v),
            ),
            const SizedBox(height: 8),
            Text(
              t.autoScheduleHelp,
              style: theme.textTheme.bodySmall
                  ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(t.cancel)),
        FilledButton(
          onPressed: () => Navigator.pop(context, (
            startMonth: _startMonth,
            months: _months,
            replaceExisting: _replaceExisting,
          )),
          child: Text(t.generate),
        ),
      ],
    );
  }
}

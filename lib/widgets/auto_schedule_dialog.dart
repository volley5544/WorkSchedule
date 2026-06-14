import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

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
    return AlertDialog(
      title: const Text('Auto schedule'),
      content: SizedBox(
        width: 360,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Start month', style: theme.textTheme.labelLarge),
            Row(
              children: [
                IconButton(
                  tooltip: 'Previous month',
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
                  tooltip: 'Next month',
                  icon: const Icon(Icons.chevron_right),
                  onPressed: () => _shiftStart(1),
                ),
              ],
            ),
            const SizedBox(height: 12),
            DropdownButtonFormField<int>(
              initialValue: _months,
              decoration: const InputDecoration(
                labelText: 'Months to fill',
                border: OutlineInputBorder(),
              ),
              items: [
                for (var m = 1; m <= 6; m++)
                  DropdownMenuItem(
                      value: m, child: Text('$m month${m == 1 ? '' : 's'}')),
              ],
              onChanged: (m) {
                if (m != null) setState(() => _months = m);
              },
            ),
            const SizedBox(height: 8),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Regenerate existing months'),
              subtitle: Text(
                _replaceExisting
                    ? 'All shifts in the selected months are deleted and '
                        'rescheduled from scratch.'
                    : 'Existing shifts are kept; only empty slots are '
                        'filled.',
                style: theme.textTheme.bodySmall,
              ),
              value: _replaceExisting,
              onChanged: (v) => setState(() => _replaceExisting = v),
            ),
            const SizedBox(height: 8),
            Text(
              'Assigns one pharmacist per shift in queue order '
              '(1 → 2 → 3 → …), day by day, for every shift type active on '
              'that weekday. The rotation continues from the last shift of '
              'the month before the start month.',
              style: theme.textTheme.bodySmall
                  ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel')),
        FilledButton(
          onPressed: () => Navigator.pop(context, (
            startMonth: _startMonth,
            months: _months,
            replaceExisting: _replaceExisting,
          )),
          child: const Text('Generate'),
        ),
      ],
    );
  }
}

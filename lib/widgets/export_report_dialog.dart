import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../l10n/app_text.dart';

/// What the user picked in the HR export dialog: a start month, how many months
/// to include, and whether to export the read-only Original baseline (instead
/// of the live, swapped roster).
typedef ExportReportRequest = ({
  DateTime startMonth,
  int months,
  bool useOriginal,
});

/// Asks for the month range and data source to export. Defaults the start to
/// [initialMonth] (the month currently on screen). Returns null if cancelled.
Future<ExportReportRequest?> showExportReportDialog(
  BuildContext context, {
  required DateTime initialMonth,
}) {
  return showDialog<ExportReportRequest>(
    context: context,
    builder: (_) => _ExportReportDialog(initialMonth: initialMonth),
  );
}

class _ExportReportDialog extends StatefulWidget {
  const _ExportReportDialog({required this.initialMonth});

  final DateTime initialMonth;

  @override
  State<_ExportReportDialog> createState() => _ExportReportDialogState();
}

class _ExportReportDialogState extends State<_ExportReportDialog> {
  late DateTime _startMonth =
      DateTime(widget.initialMonth.year, widget.initialMonth.month);
  int _months = 1;
  bool _useOriginal = false;

  void _shiftStart(int delta) {
    setState(() =>
        _startMonth = DateTime(_startMonth.year, _startMonth.month + delta));
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final t = AppText.of(context);
    return AlertDialog(
      title: Text(t.exportReport),
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
                labelText: t.monthsToExport,
                border: const OutlineInputBorder(),
              ),
              items: [
                for (var m = 1; m <= 12; m++)
                  DropdownMenuItem(value: m, child: Text(t.monthCount(m))),
              ],
              onChanged: (m) {
                if (m != null) setState(() => _months = m);
              },
            ),
            const SizedBox(height: 16),
            Text(t.exportSource, style: theme.textTheme.labelLarge),
            const SizedBox(height: 6),
            SegmentedButton<bool>(
              showSelectedIcon: false,
              segments: [
                ButtonSegment(
                  value: false,
                  icon: const Icon(Icons.table_chart, size: 18),
                  label: Text(t.exportSourceLive),
                ),
                ButtonSegment(
                  value: true,
                  icon: const Icon(Icons.lock_outline, size: 18),
                  label: Text(t.exportSourceOriginal),
                ),
              ],
              selected: {_useOriginal},
              onSelectionChanged: (s) =>
                  setState(() => _useOriginal = s.first),
            ),
            const SizedBox(height: 6),
            Text(
              _useOriginal
                  ? t.exportSourceOriginalHelp
                  : t.exportSourceLiveHelp,
              style: theme.textTheme.bodySmall
                  ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text(t.cancel),
        ),
        FilledButton.icon(
          onPressed: () => Navigator.pop(context, (
            startMonth: _startMonth,
            months: _months,
            useOriginal: _useOriginal,
          )),
          icon: const Icon(Icons.file_download_outlined, size: 18),
          label: Text(t.exportAction),
        ),
      ],
    );
  }
}

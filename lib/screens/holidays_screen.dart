import 'package:flutter/material.dart';

import '../models/holiday.dart';
import '../models/shift.dart';
import '../services/schedule_service.dart';
import '../utils/thai_date.dart';

/// Clinic holidays (closed days), shown to any signed-in user. Admins can also
/// add / edit / remove them and seed the posted list; everyone else sees a
/// read-only list. Dates are shown in Thai with Buddhist-era years.
class HolidaysScreen extends StatelessWidget {
  const HolidaysScreen({
    super.key,
    required this.service,
    this.canManage = false,
  });

  final ScheduleService service;

  /// Admins only: whether the add / edit / remove / seed actions are shown.
  final bool canManage;

  Future<void> _edit(BuildContext context, {Holiday? existing}) async {
    final result = await showDialog<Holiday>(
      context: context,
      builder: (_) => _HolidayDialog(existing: existing),
    );
    if (result == null || !context.mounted) return;
    try {
      await service.saveHoliday(result);
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Could not save holiday: $e')));
      }
    }
  }

  Future<void> _delete(BuildContext context, Holiday holiday) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Remove holiday ${thaiShortDate(holiday.date)}?'),
        content: Text(holiday.name.isEmpty ? '' : holiday.name),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          FilledButton.tonal(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Remove'),
          ),
        ],
      ),
    );
    if (confirmed != true || !context.mounted) return;
    try {
      await service.deleteHoliday(holiday.dateKey);
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Could not remove holiday: $e')));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<List<Holiday>>(
      stream: service.holidays(),
      builder: (context, snap) {
        final holidays = snap.data ?? const <Holiday>[];
        return Scaffold(
          appBar: AppBar(title: const Text('Holidays')),
          floatingActionButton: canManage
              ? FloatingActionButton.extended(
                  onPressed: () => _edit(context),
                  icon: const Icon(Icons.add),
                  label: const Text('Add holiday'),
                )
              : null,
          body: Builder(
            builder: (context) {
              if (snap.hasError) {
                return Center(
                  child: Text('Failed to load holidays: ${snap.error}'),
                );
              }
              if (!snap.hasData) {
                return const Center(child: CircularProgressIndicator());
              }
              if (holidays.isEmpty) {
                return _EmptyState(service: service, canManage: canManage);
              }
              return ListView.separated(
                padding: const EdgeInsets.fromLTRB(8, 8, 8, 88),
                itemCount: holidays.length,
                separatorBuilder: (_, _) => const Divider(height: 1),
                itemBuilder: (context, i) {
                  final holiday = holidays[i];
                  final theme = Theme.of(context);
                  return ListTile(
                    leading: CircleAvatar(
                      backgroundColor: theme.colorScheme.errorContainer,
                      child: Icon(
                        Icons.event_busy,
                        color: theme.colorScheme.onErrorContainer,
                        size: 20,
                      ),
                    ),
                    title: Text(
                      thaiFullDate(holiday.date),
                      style: const TextStyle(fontWeight: FontWeight.w600),
                    ),
                    subtitle: holiday.name.isEmpty ? null : Text(holiday.name),
                    trailing: canManage
                        ? IconButton(
                            tooltip: 'Remove',
                            icon: const Icon(Icons.delete_outline),
                            onPressed: () => _delete(context, holiday),
                          )
                        : null,
                    onTap: canManage
                        ? () => _edit(context, existing: holiday)
                        : null,
                  );
                },
              );
            },
          ),
        );
      },
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState({required this.service, required this.canManage});

  final ScheduleService service;
  final bool canManage;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.event_busy, size: 56, color: theme.colorScheme.outline),
          const SizedBox(height: 12),
          Text(
            canManage
                ? 'No holidays configured yet.'
                : 'No holidays have been set yet.',
          ),
          if (canManage) ...[
            const SizedBox(height: 16),
            FilledButton.icon(
              icon: const Icon(Icons.playlist_add),
              label: const Text('Add 2569 clinic holidays'),
              onPressed: () async {
                try {
                  await service.seedHolidays2569();
                } catch (e) {
                  if (context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text('Could not add holidays: $e')),
                    );
                  }
                }
              },
            ),
          ],
        ],
      ),
    );
  }
}

class _HolidayDialog extends StatefulWidget {
  const _HolidayDialog({this.existing});

  final Holiday? existing;

  @override
  State<_HolidayDialog> createState() => _HolidayDialogState();
}

class _HolidayDialogState extends State<_HolidayDialog> {
  late DateTime _date = widget.existing?.date ?? DateTime.now();
  late final _nameCtrl = TextEditingController(
    text: widget.existing?.name ?? 'วันหยุดคลินิกพิเศษ',
  );

  bool get _isNew => widget.existing == null;

  @override
  void dispose() {
    _nameCtrl.dispose();
    super.dispose();
  }

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _date,
      firstDate: DateTime(DateTime.now().year - 1),
      lastDate: DateTime(DateTime.now().year + 3, 12, 31),
    );
    if (picked != null) setState(() => _date = picked);
  }

  void _submit() {
    Navigator.pop(
      context,
      Holiday(
        id: '',
        dateKey: Shift.keyFor(_date),
        name: _nameCtrl.text.trim(),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(_isNew ? 'Add holiday' : 'Edit holiday'),
      content: SizedBox(
        width: 360,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            OutlinedButton.icon(
              icon: const Icon(Icons.calendar_today, size: 18),
              label: Text(thaiFullDate(_date)),
              onPressed: _pickDate,
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _nameCtrl,
              decoration: const InputDecoration(
                labelText: 'Name / reason',
                border: OutlineInputBorder(),
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        FilledButton(onPressed: _submit, child: const Text('Save')),
      ],
    );
  }
}

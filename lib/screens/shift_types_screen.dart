import 'package:flutter/material.dart';

import '../models/shift_type.dart';
import '../services/schedule_service.dart';

/// Admin-only screen for configuring the shift types (code, hours, color)
/// available when scheduling.
class ShiftTypesScreen extends StatelessWidget {
  const ShiftTypesScreen({super.key, required this.service});

  final ScheduleService service;

  Future<void> _edit(BuildContext context,
      {ShiftType? existing, required int nextSortOrder}) async {
    final result = await showDialog<ShiftType>(
      context: context,
      builder: (_) =>
          _ShiftTypeDialog(existing: existing, nextSortOrder: nextSortOrder),
    );
    if (result == null || !context.mounted) return;
    try {
      await service.saveShiftType(result);
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not save shift type: $e')),
        );
      }
    }
  }

  Future<void> _delete(BuildContext context, ShiftType type) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Delete shift type "${type.label}"?'),
        content: const Text(
            'Shifts already on the roster keep their saved times but will '
            'show in grey as an unknown type.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancel')),
          FilledButton.tonal(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Delete')),
        ],
      ),
    );
    if (confirmed != true || !context.mounted) return;
    try {
      await service.deleteShiftType(type.id);
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not delete shift type: $e')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<List<ShiftType>>(
      stream: service.shiftTypes(),
      builder: (context, snap) {
        final types = snap.data ?? const <ShiftType>[];
        final nextSortOrder =
            types.isEmpty ? 0 : types.last.sortOrder + 1;
        return Scaffold(
          appBar: AppBar(title: const Text('Shift types')),
          floatingActionButton: FloatingActionButton.extended(
            onPressed: () => _edit(context, nextSortOrder: nextSortOrder),
            icon: const Icon(Icons.add),
            label: const Text('Add shift type'),
          ),
          body: Builder(builder: (context) {
            if (snap.hasError) {
              return Center(
                  child: Text('Failed to load shift types: ${snap.error}'));
            }
            if (!snap.hasData) {
              return const Center(child: CircularProgressIndicator());
            }
            if (types.isEmpty) return _EmptyState(service: service);
            return ListView.separated(
              padding: const EdgeInsets.fromLTRB(8, 8, 8, 88),
              itemCount: types.length,
              separatorBuilder: (_, _) => const Divider(height: 1),
              itemBuilder: (context, i) {
                final type = types[i];
                return ListTile(
                  leading: CircleAvatar(
                    backgroundColor: type.color,
                    child: Text(
                      type.label,
                      style: const TextStyle(
                          color: Colors.white, fontWeight: FontWeight.bold),
                    ),
                  ),
                  title: Text(
                      type.description.isEmpty
                          ? type.label
                          : '${type.label} · ${type.description}',
                      style: const TextStyle(fontWeight: FontWeight.w600)),
                  subtitle:
                      Text('${type.start}–${type.end} · ${type.daysLabel}'),
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      IconButton(
                        tooltip: 'Edit',
                        icon: const Icon(Icons.edit_outlined),
                        onPressed: () => _edit(context,
                            existing: type, nextSortOrder: nextSortOrder),
                      ),
                      IconButton(
                        tooltip: 'Delete',
                        icon: const Icon(Icons.delete_outline),
                        onPressed: () => _delete(context, type),
                      ),
                    ],
                  ),
                );
              },
            );
          }),
        );
      },
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState({required this.service});

  final ScheduleService service;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.schedule, size: 56, color: theme.colorScheme.outline),
          const SizedBox(height: 12),
          const Text('No shift types configured yet.'),
          const SizedBox(height: 16),
          FilledButton.icon(
            icon: const Icon(Icons.playlist_add),
            label: const Text('Add hospital defaults (ช ย บ ด)'),
            onPressed: () async {
              try {
                await service.seedDefaultShiftTypes();
              } catch (e) {
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text('Could not add defaults: $e')),
                  );
                }
              }
            },
          ),
        ],
      ),
    );
  }
}

const _palette = [
  Color(0xFFF59E0B),
  Color(0xFFEF4444),
  Color(0xFFEC4899),
  Color(0xFF8B5CF6),
  Color(0xFF6366F1),
  Color(0xFF3B82F6),
  Color(0xFF0EA5E9),
  Color(0xFF14B8A6),
  Color(0xFF22C55E),
  Color(0xFF84CC16),
  Color(0xFF78716C),
  Color(0xFF64748B),
];

class _ShiftTypeDialog extends StatefulWidget {
  const _ShiftTypeDialog({this.existing, required this.nextSortOrder});

  final ShiftType? existing;
  final int nextSortOrder;

  @override
  State<_ShiftTypeDialog> createState() => _ShiftTypeDialogState();
}

class _ShiftTypeDialogState extends State<_ShiftTypeDialog> {
  final _formKey = GlobalKey<FormState>();
  late final _labelCtrl =
      TextEditingController(text: widget.existing?.label ?? '');
  late final _descriptionCtrl =
      TextEditingController(text: widget.existing?.description ?? '');
  late String _start = widget.existing?.start ?? '08:30';
  late String _end = widget.existing?.end ?? '16:30';
  late Color _color = widget.existing?.color ?? _palette.first;
  late final Set<int> _days = {...widget.existing?.days ?? ShiftType.everyDay};

  static const _dayNames = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];

  bool get _isNew => widget.existing == null;

  @override
  void dispose() {
    _labelCtrl.dispose();
    _descriptionCtrl.dispose();
    super.dispose();
  }

  Future<void> _pickTime(bool isStart) async {
    final parts = (isStart ? _start : _end).split(':');
    final picked = await showTimePicker(
      context: context,
      initialTime: TimeOfDay(
        hour: int.tryParse(parts[0]) ?? 8,
        minute: int.tryParse(parts.length > 1 ? parts[1] : '0') ?? 0,
      ),
    );
    if (picked == null) return;
    final formatted =
        '${picked.hour.toString().padLeft(2, '0')}:${picked.minute.toString().padLeft(2, '0')}';
    setState(() => isStart ? _start = formatted : _end = formatted);
  }

  void _submit() {
    if (!_formKey.currentState!.validate()) return;
    if (_days.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Select at least one active day.')),
      );
      return;
    }
    Navigator.pop(
      context,
      ShiftType(
        id: widget.existing?.id ?? '',
        label: _labelCtrl.text.trim(),
        description: _descriptionCtrl.text.trim(),
        start: _start,
        end: _end,
        color: _color,
        days: [..._days]..sort(),
        sortOrder: widget.existing?.sortOrder ?? widget.nextSortOrder,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(_isNew ? 'Add shift type' : 'Edit shift type'),
      content: Form(
        key: _formKey,
        child: SizedBox(
          width: 360,
          child: ListView(
            shrinkWrap: true,
            children: [
              TextFormField(
                controller: _labelCtrl,
                decoration: const InputDecoration(
                  labelText: 'Code / name (e.g. ช)',
                  border: OutlineInputBorder(),
                ),
                validator: (v) => (v == null || v.trim().isEmpty)
                    ? 'Enter a code for the shift'
                    : null,
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _descriptionCtrl,
                decoration: const InputDecoration(
                  labelText: 'Description (optional, e.g. เวรเช้า)',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 12),
              Row(children: [
                Expanded(
                  child: OutlinedButton.icon(
                    icon: const Icon(Icons.schedule, size: 18),
                    label: Text(_start),
                    onPressed: () => _pickTime(true),
                  ),
                ),
                const Padding(
                    padding: EdgeInsets.symmetric(horizontal: 8),
                    child: Text('–')),
                Expanded(
                  child: OutlinedButton.icon(
                    icon: const Icon(Icons.schedule, size: 18),
                    label: Text(_end),
                    onPressed: () => _pickTime(false),
                  ),
                ),
              ]),
              const SizedBox(height: 16),
              Text('Active days',
                  style: Theme.of(context).textTheme.labelLarge),
              const SizedBox(height: 8),
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: [
                  for (var d = 1; d <= 7; d++)
                    FilterChip(
                      label: Text(_dayNames[d - 1]),
                      visualDensity: VisualDensity.compact,
                      selected: _days.contains(d),
                      onSelected: (selected) => setState(() =>
                          selected ? _days.add(d) : _days.remove(d)),
                    ),
                ],
              ),
              const SizedBox(height: 16),
              Text('Color', style: Theme.of(context).textTheme.labelLarge),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final color in _palette)
                    InkWell(
                      borderRadius: BorderRadius.circular(16),
                      onTap: () => setState(() => _color = color),
                      child: Container(
                        width: 32,
                        height: 32,
                        decoration: BoxDecoration(
                          color: color,
                          shape: BoxShape.circle,
                          border: color == _color
                              ? Border.all(
                                  width: 3,
                                  color:
                                      Theme.of(context).colorScheme.onSurface)
                              : null,
                        ),
                        child: color == _color
                            ? const Icon(Icons.check,
                                size: 16, color: Colors.white)
                            : null,
                      ),
                    ),
                ],
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel')),
        FilledButton(onPressed: _submit, child: const Text('Save')),
      ],
    );
  }
}

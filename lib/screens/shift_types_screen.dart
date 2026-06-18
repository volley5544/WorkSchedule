import 'package:flutter/material.dart';

import '../models/pharmacist.dart';
import '../models/shift_type.dart';
import '../services/schedule_service.dart';

/// Admin-only screen for configuring the shift types (code, hours, color,
/// holiday behaviour, and an optional custom rotation) available when
/// scheduling.
class ShiftTypesScreen extends StatelessWidget {
  const ShiftTypesScreen({
    super.key,
    required this.service,
    this.pharmacists = const [],
  });

  final ScheduleService service;

  /// Roster, in queue order — offered as the participants of a custom rotation.
  final List<Pharmacist> pharmacists;

  Future<void> _edit(BuildContext context,
      {ShiftType? existing,
      required int nextSortOrder,
      required List<ShiftType> allTypes}) async {
    final result = await showDialog<ShiftType>(
      context: context,
      builder: (_) => _ShiftTypeDialog(
        existing: existing,
        nextSortOrder: nextSortOrder,
        pharmacists: pharmacists,
        allTypes: allTypes,
      ),
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

  Future<void> _reorder(
    BuildContext context,
    List<ShiftType> types,
    int oldIndex,
    int newIndex,
  ) async {
    // ReorderableListView reports newIndex as the slot before removal.
    if (newIndex > oldIndex) newIndex -= 1;
    if (newIndex == oldIndex) return;
    final reordered = [...types];
    reordered.insert(newIndex, reordered.removeAt(oldIndex));
    try {
      await service.reorderShiftTypes(reordered.map((t) => t.id).toList());
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not reorder shift types: $e')),
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
            onPressed: () =>
                _edit(context, nextSortOrder: nextSortOrder, allTypes: types),
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
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
                  child: Text(
                    'Drag the handle to reorder. This order is the priority the '
                    'auto-scheduler assigns shifts in each day (top first).',
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color:
                              Theme.of(context).colorScheme.onSurfaceVariant,
                        ),
                  ),
                ),
                Expanded(
                  child: ReorderableListView.builder(
                    padding: const EdgeInsets.fromLTRB(8, 8, 8, 88),
                    buildDefaultDragHandles: false,
                    itemCount: types.length,
                    onReorder: (oldIndex, newIndex) =>
                        _reorder(context, types, oldIndex, newIndex),
                    itemBuilder: (context, i) {
                      final type = types[i];
                      return Column(
                        key: ValueKey(type.id),
                        children: [
                          ListTile(
                            leading: CircleAvatar(
                              backgroundColor: type.color,
                              child: Text(
                                type.label,
                                style: const TextStyle(
                                    color: Colors.white,
                                    fontWeight: FontWeight.bold),
                              ),
                            ),
                            title: Text(
                                type.description.isEmpty
                                    ? type.label
                                    : '${type.label} · ${type.description}',
                                style: const TextStyle(
                                    fontWeight: FontWeight.w600)),
                            subtitle: Text(_subtitleFor(type)),
                            isThreeLine: type.onHoliday ||
                                type.singleRotation ||
                                type.hasWeekdayPins ||
                                type.hasCustomRoster ||
                                type.isLinked,
                            trailing: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                ReorderableDragStartListener(
                                  index: i,
                                  child: const Padding(
                                    padding:
                                        EdgeInsets.symmetric(horizontal: 4),
                                    child: Icon(Icons.drag_handle),
                                  ),
                                ),
                                IconButton(
                                  tooltip: 'Edit',
                                  icon: const Icon(Icons.edit_outlined),
                                  onPressed: () => _edit(context,
                                      existing: type,
                                      nextSortOrder: nextSortOrder,
                                      allTypes: types),
                                ),
                                IconButton(
                                  tooltip: 'Delete',
                                  icon: const Icon(Icons.delete_outline),
                                  onPressed: () => _delete(context, type),
                                ),
                              ],
                            ),
                          ),
                          const Divider(height: 1),
                        ],
                      );
                    },
                  ),
                ),
              ],
            );
          }),
        );
      },
    );
  }

  /// One-line config summary: hours · active days, then holiday/rotation flags.
  String _subtitleFor(ShiftType type) {
    final holidaysOnly = type.days.isEmpty && type.onHoliday;
    final flags = <String>[
      if (type.singleRotation) 'Every day · one shared rotation',
      if (type.onHoliday && !holidaysOnly && !type.singleRotation)
        'Runs on holidays',
      if (type.hasWeekdayPins) 'Weekday pins (${type.weekdayPins.length})',
      if (type.isLinked) 'Linked rotation',
      if (type.hasCustomRoster)
        'Custom rotation (${type.roster.length})',
    ];
    final daysPart = type.singleRotation
        ? 'Every day'
        : holidaysOnly
            ? 'Holidays only'
            : type.daysLabel;
    final base = '${type.start}–${type.end} · $daysPart';
    return flags.isEmpty ? base : '$base\n${flags.join(' · ')}';
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

const _dayNames = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];

class _ShiftTypeDialog extends StatefulWidget {
  const _ShiftTypeDialog({
    this.existing,
    required this.nextSortOrder,
    required this.pharmacists,
    required this.allTypes,
  });

  final ShiftType? existing;
  final int nextSortOrder;
  final List<Pharmacist> pharmacists;

  /// All configured types, used to offer a shift to "link" this one to.
  final List<ShiftType> allTypes;

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
  late bool _onHoliday = widget.existing?.onHoliday ?? false;
  late bool _singleRotation = widget.existing?.singleRotation ?? false;

  /// Participants of the custom rotation. Empty = rotate through the global
  /// queue (the default). Pre-seeded from the existing type when editing.
  late final List<RosterEntry> _roster = [...?widget.existing?.roster];
  late bool _customRotation = _roster.isNotEmpty;

  /// Weekday (1=Mon…7=Sun) → pinned pharmacist id. Applies on any day this
  /// shift runs on that weekday (normal day, weekend, or holiday); unmapped
  /// weekdays use the rotation.
  late final Map<int, String> _weekdayPins = {
    ...?widget.existing?.weekdayPins,
  };

  /// Id of the shift type this one is linked to (same pharmacist), or null.
  late String? _followsTypeId =
      (widget.existing?.followsTypeId.isNotEmpty ?? false)
          ? widget.existing!.followsTypeId
          : null;

  /// Other types that can be linked to (everything except this one).
  List<ShiftType> get _otherTypes =>
      widget.allTypes.where((t) => t.id != widget.existing?.id).toList();

  bool get _isNew => widget.existing == null;

  Pharmacist? _pharmacistById(String id) {
    for (final p in widget.pharmacists) {
      if (p.id == id) return p;
    }
    return null;
  }

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

  void _toggleCustomRotation(bool on) {
    setState(() {
      _customRotation = on;
      // Seed with the whole queue so the admin has something to reorder/trim.
      if (on && _roster.isEmpty) {
        _roster.addAll(
          widget.pharmacists.map((p) => RosterEntry(pharmacistId: p.id)),
        );
      }
    });
  }

  void _addParticipant() {
    final inRoster = _roster.map((e) => e.pharmacistId).toSet();
    final available =
        widget.pharmacists.where((p) => !inRoster.contains(p.id)).toList()
          ..sort(Pharmacist.byShowOrder);
    if (available.isEmpty) return;
    showDialog<Pharmacist>(
      context: context,
      builder: (ctx) => SimpleDialog(
        title: const Text('Add pharmacist'),
        children: [
          for (final p in available)
            SimpleDialogOption(
              onPressed: () => Navigator.pop(ctx, p),
              child: Text(p.displayName),
            ),
        ],
      ),
    ).then((p) {
      if (p != null) {
        setState(() => _roster.add(RosterEntry(pharmacistId: p.id)));
      }
    });
  }

  void _onReorder(int oldIndex, int newIndex) {
    setState(() {
      // ReorderableListView reports newIndex as the slot *before* removal.
      if (newIndex > oldIndex) newIndex -= 1;
      final entry = _roster.removeAt(oldIndex);
      _roster.insert(newIndex, entry);
    });
  }

  Future<void> _editConstraints(int index) async {
    final updated = await showDialog<RosterEntry>(
      context: context,
      builder: (_) => _ConstraintsDialog(entry: _roster[index]),
    );
    if (updated != null) setState(() => _roster[index] = updated);
  }

  String _constraintSummary(RosterEntry e) {
    if (!e.isConstrained) return 'Every day this shift runs';
    const ordinals = ['1st', '2nd', '3rd', '4th', '5th'];
    final parts = <String>[];
    if (e.weekdays.isNotEmpty) {
      final sorted = [...e.weekdays]..sort();
      parts.add(sorted.map((d) => _dayNames[d - 1]).join(', '));
    }
    if (e.monthWeeks.isNotEmpty) {
      final sorted = [...e.monthWeeks]..sort();
      parts.add(sorted.map((w) => ordinals[w - 1]).join(', '));
    }
    if (e.parity != WeekParity.every) parts.add(e.parity.label);
    return parts.join(' · ');
  }

  void _submit() {
    if (!_formKey.currentState!.validate()) return;
    // No active days is allowed only for a holiday-only shift; otherwise the
    // type would never be scheduled.
    if (_days.isEmpty && !_onHoliday && !_singleRotation) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Select at least one active day, or turn on "Runs on holidays" '
            'for a holiday-only shift.',
          ),
        ),
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
        onHoliday: _onHoliday,
        singleRotation: _singleRotation,
        roster: _customRotation ? List.of(_roster) : const [],
        weekdayPins: Map.of(_weekdayPins),
        followsTypeId: _followsTypeId ?? '',
        sortOrder: widget.existing?.sortOrder ?? widget.nextSortOrder,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return AlertDialog(
      title: Text(_isNew ? 'Add shift type' : 'Edit shift type'),
      content: Form(
        key: _formKey,
        child: SizedBox(
          width: 380,
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
              Text('Active days', style: theme.textTheme.labelLarge),
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
              if (_days.isEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Text(
                    'No active days — this shift only runs on holidays '
                    '(turn on "Runs on holidays" below).',
                    style: theme.textTheme.bodySmall
                        ?.copyWith(color: theme.colorScheme.primary),
                  ),
                ),
              if (widget.pharmacists.isNotEmpty)
                ..._buildWeekdayPins(theme),
              const SizedBox(height: 4),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Runs on holidays'),
                subtitle: Text(
                  'A holiday is a non-working day; only types with this on are '
                  'scheduled then (active days are ignored).',
                  style: theme.textTheme.bodySmall,
                ),
                value: _onHoliday,
                onChanged: (v) => setState(() => _onHoliday = v),
              ),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('One shared rotation, every day'),
                subtitle: Text(
                  'Runs every day — weekday, weekend and holiday alike (active '
                  'days and "Runs on holidays" are ignored) — and rotates as a '
                  'single continuous cycle instead of separate '
                  'weekday/weekend/holiday rotations. Use for ด (night duty).',
                  style: theme.textTheme.bodySmall,
                ),
                value: _singleRotation,
                onChanged: (v) => setState(() => _singleRotation = v),
              ),
              if (_otherTypes.isNotEmpty) ...[
                const Divider(height: 24),
                Text('Same pharmacist as', style: theme.textTheme.labelLarge),
                Text(
                  'On days the chosen shift runs, this shift is given the same '
                  'pharmacist instead of rotating (e.g. บ follows ช on '
                  'weekends/holidays). On other days it rotates normally.',
                  style: theme.textTheme.bodySmall,
                ),
                const SizedBox(height: 4),
                DropdownButton<String?>(
                  isExpanded: true,
                  value: _followsTypeId,
                  items: [
                    const DropdownMenuItem<String?>(
                      value: null,
                      child: Text('None (rotate independently)'),
                    ),
                    for (final t in _otherTypes)
                      DropdownMenuItem<String?>(
                        value: t.id,
                        child: Text(
                          t.description.isEmpty
                              ? t.label
                              : '${t.label} · ${t.description}',
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                  ],
                  onChanged: (v) => setState(() => _followsTypeId = v),
                ),
              ],
              const Divider(height: 24),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Custom rotation'),
                subtitle: Text(
                  _customRotation
                      ? 'Rotate through the pharmacists below, in this order.'
                      : 'Off: rotate through the global queue order.',
                  style: theme.textTheme.bodySmall,
                ),
                value: _customRotation,
                onChanged: widget.pharmacists.isEmpty
                    ? null
                    : _toggleCustomRotation,
              ),
              if (widget.pharmacists.isEmpty)
                Text(
                  'Add pharmacists first to configure a custom rotation.',
                  style: theme.textTheme.bodySmall
                      ?.copyWith(color: theme.colorScheme.error),
                ),
              if (_customRotation) ..._buildRosterEditor(theme),
              const SizedBox(height: 16),
              Text('Color', style: theme.textTheme.labelLarge),
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
                                  color: theme.colorScheme.onSurface)
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

  List<Widget> _buildWeekdayPins(ThemeData theme) {
    return [
      const SizedBox(height: 12),
      Text('Pin pharmacist by weekday', style: theme.textTheme.labelLarge),
      Text(
        'Optionally fix a pharmacist for this shift on a given weekday — on '
        'normal days, weekends, and holidays alike. The rest use the rotation.',
        style: theme.textTheme.bodySmall,
      ),
      const SizedBox(height: 4),
      for (var d = 1; d <= 7; d++)
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 2),
          child: Row(
            children: [
              SizedBox(width: 40, child: Text(_dayNames[d - 1])),
              const SizedBox(width: 8),
              Expanded(
                child: DropdownButton<String?>(
                  isExpanded: true,
                  value: _weekdayPins[d],
                  underline: const SizedBox.shrink(),
                  items: [
                    const DropdownMenuItem<String?>(
                      value: null,
                      child: Text('Use rotation'),
                    ),
                    for (final p in widget.pharmacists)
                      DropdownMenuItem<String?>(
                        value: p.id,
                        child: Text(p.displayName,
                            overflow: TextOverflow.ellipsis),
                      ),
                  ],
                  onChanged: (id) => setState(() {
                    if (id == null) {
                      _weekdayPins.remove(d);
                    } else {
                      _weekdayPins[d] = id;
                    }
                  }),
                ),
              ),
            ],
          ),
        ),
    ];
  }

  List<Widget> _buildRosterEditor(ThemeData theme) {
    final canAdd = _roster.length < widget.pharmacists.length;
    return [
      const SizedBox(height: 4),
      if (_roster.isEmpty)
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 8),
          child: Text(
            'No pharmacists in the rotation yet.',
            style: theme.textTheme.bodySmall,
          ),
        )
      else
        Text(
          'Drag the handle to reorder the turn order.',
          style: theme.textTheme.bodySmall,
        ),
      ReorderableListView.builder(
        shrinkWrap: true,
        // The surrounding dialog ListView handles scrolling; this list just
        // lays its rows out inline.
        physics: const NeverScrollableScrollPhysics(),
        buildDefaultDragHandles: false,
        itemCount: _roster.length,
        onReorder: _onReorder,
        itemBuilder: (context, i) {
          final entry = _roster[i];
          return _RosterRow(
            // ValueKey keeps row state stable across reorders.
            key: ValueKey(entry.pharmacistId),
            index: i,
            position: i + 1,
            name: _pharmacistById(entry.pharmacistId)?.displayName ??
                'Unknown pharmacist',
            constraintLabel: _constraintSummary(entry),
            constrained: entry.isConstrained,
            onEdit: () => _editConstraints(i),
            onRemove: () => setState(() => _roster.removeAt(i)),
          );
        },
      ),
      Align(
        alignment: Alignment.centerLeft,
        child: TextButton.icon(
          onPressed: canAdd ? _addParticipant : null,
          icon: const Icon(Icons.person_add_alt, size: 18),
          label: const Text('Add pharmacist'),
        ),
      ),
    ];
  }
}

/// A single drag-to-reorder row in the custom-rotation editor.
class _RosterRow extends StatelessWidget {
  const _RosterRow({
    super.key,
    required this.index,
    required this.position,
    required this.name,
    required this.constraintLabel,
    required this.constrained,
    required this.onEdit,
    required this.onRemove,
  });

  /// Position in the rotation list, needed by the drag-start listener.
  final int index;
  final int position;
  final String name;
  final String constraintLabel;
  final bool constrained;
  final VoidCallback onEdit;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        children: [
          ReorderableDragStartListener(
            index: index,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4),
              child: Icon(Icons.drag_handle,
                  color: theme.colorScheme.onSurfaceVariant),
            ),
          ),
          SizedBox(
            width: 22,
            child: Text('$position.',
                style: theme.textTheme.labelMedium,
                textAlign: TextAlign.end),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(name, maxLines: 1, overflow: TextOverflow.ellipsis),
                Text(
                  constraintLabel,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: constrained
                        ? theme.colorScheme.primary
                        : theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
          IconButton(
            visualDensity: VisualDensity.compact,
            tooltip: 'Day / week rules',
            icon: Icon(
              constrained ? Icons.tune : Icons.tune_outlined,
              color: constrained ? theme.colorScheme.primary : null,
            ),
            onPressed: onEdit,
          ),
          IconButton(
            visualDensity: VisualDensity.compact,
            tooltip: 'Remove',
            icon: const Icon(Icons.close),
            onPressed: onRemove,
          ),
        ],
      ),
    );
  }
}

/// Edits a roster entry's per-type weekday + week-parity constraints (the 'ณ'
/// case: "only Thursdays, every other week").
class _ConstraintsDialog extends StatefulWidget {
  const _ConstraintsDialog({required this.entry});

  final RosterEntry entry;

  @override
  State<_ConstraintsDialog> createState() => _ConstraintsDialogState();
}

class _ConstraintsDialogState extends State<_ConstraintsDialog> {
  late final Set<int> _weekdays = {...widget.entry.weekdays};
  late WeekParity _parity = widget.entry.parity;
  late final Set<int> _monthWeeks = {...widget.entry.monthWeeks};

  static const _ordinals = ['1st', '2nd', '3rd', '4th', '5th'];

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return AlertDialog(
      title: const Text('Day / week rules'),
      content: SizedBox(
        width: 340,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Limit this pharmacist to certain weekdays for this shift. '
              'Leave all off to allow every day the shift runs.',
              style: theme.textTheme.bodySmall,
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                for (var d = 1; d <= 7; d++)
                  FilterChip(
                    label: Text(_dayNames[d - 1]),
                    visualDensity: VisualDensity.compact,
                    selected: _weekdays.contains(d),
                    onSelected: (s) => setState(
                        () => s ? _weekdays.add(d) : _weekdays.remove(d)),
                  ),
              ],
            ),
            const SizedBox(height: 16),
            Text('Weeks of the month', style: theme.textTheme.labelLarge),
            const SizedBox(height: 4),
            Text(
              'Limit to certain occurrences of the weekday in the month — e.g. '
              'only the 5th, or 1st–4th to skip a 5th one. Leave all off for '
              'every occurrence.',
              style: theme.textTheme.bodySmall,
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                for (var w = 1; w <= 5; w++)
                  FilterChip(
                    label: Text(_ordinals[w - 1]),
                    visualDensity: VisualDensity.compact,
                    selected: _monthWeeks.contains(w),
                    onSelected: (s) => setState(
                        () => s ? _monthWeeks.add(w) : _monthWeeks.remove(w)),
                  ),
              ],
            ),
            const SizedBox(height: 16),
            Text('Week pattern', style: theme.textTheme.labelLarge),
            const SizedBox(height: 4),
            Text(
              'Week A / Week B alternate every calendar week, so a pharmacist '
              'can work "every other week".',
              style: theme.textTheme.bodySmall,
            ),
            const SizedBox(height: 8),
            for (final p in WeekParity.values)
              RadioListTile<WeekParity>(
                contentPadding: EdgeInsets.zero,
                dense: true,
                title: Text(p.label),
                value: p,
                // ignore: deprecated_member_use
                groupValue: _parity,
                // ignore: deprecated_member_use
                onChanged: (v) => setState(() => _parity = v ?? _parity),
              ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(
            context,
            widget.entry.copyWith(
              weekdays: [..._weekdays]..sort(),
              parity: _parity,
              monthWeeks: [..._monthWeeks]..sort(),
            ),
          ),
          child: const Text('Done'),
        ),
      ],
    );
  }
}

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../l10n/app_text.dart';
import '../models/pharmacist.dart';
import '../models/shift.dart';
import '../models/shift_type.dart';

/// Result of the editor: either a shift to save, or a request to delete.
class ShiftEditorResult {
  const ShiftEditorResult.save(this.shift) : delete = false;
  const ShiftEditorResult.delete(this.shift) : delete = true;

  final Shift shift;
  final bool delete;
}

/// Opens the create/edit dialog. Returns null if cancelled.
/// [types] and [pharmacists] are the current config and must not be empty.
Future<ShiftEditorResult?> showShiftEditor(
  BuildContext context, {
  required DateTime day,
  required List<ShiftType> types,
  required List<Pharmacist> pharmacists,
  String? presetPharmacistId,
  Shift? existing,
  required String currentUid,
}) {
  return showDialog<ShiftEditorResult>(
    context: context,
    builder: (_) => _ShiftEditorDialog(
      day: day,
      types: types,
      pharmacists: pharmacists,
      presetPharmacistId: presetPharmacistId,
      existing: existing,
      currentUid: currentUid,
    ),
  );
}

class _ShiftEditorDialog extends StatefulWidget {
  const _ShiftEditorDialog({
    required this.day,
    required this.types,
    required this.pharmacists,
    required this.currentUid,
    this.presetPharmacistId,
    this.existing,
  });

  final DateTime day;
  final List<ShiftType> types;
  final List<Pharmacist> pharmacists;
  final String? presetPharmacistId;
  final String currentUid;
  final Shift? existing;

  @override
  State<_ShiftEditorDialog> createState() => _ShiftEditorDialogState();
}

class _ShiftEditorDialogState extends State<_ShiftEditorDialog> {
  final _formKey = GlobalKey<FormState>();

  /// Editing a shift whose type was deleted keeps it selectable so the
  /// other fields can still be changed without re-typing the shift.
  late final List<ShiftType> _types = [
    ...widget.types,
    if (widget.existing != null &&
        !widget.types.any((t) => t.id == widget.existing!.typeId))
      ShiftType.unknown(widget.existing!.typeId),
  ];

  /// Same trick for the pharmacist: a shift whose pharmacist was removed
  /// from the config (or a legacy free-text shift) stays selectable under
  /// its saved name. Listed in the table display order (showOrder).
  late final List<Pharmacist> _pharmacists = [
    ...[...widget.pharmacists]..sort(Pharmacist.byShowOrder),
    if (widget.existing != null &&
        !widget.pharmacists.any((p) => p.id == widget.existing!.pharmacistId))
      Pharmacist(
        id: widget.existing!.pharmacistId,
        name: widget.existing!.pharmacist.isEmpty
            ? '(unknown)'
            : widget.existing!.pharmacist,
      ),
  ];

  late DateTime _day = widget.existing?.date ?? widget.day;
  late String _typeId = widget.existing?.typeId ?? _types.first.id;
  late String _start = widget.existing?.start ?? _types.first.start;
  late String _end = widget.existing?.end ?? _types.first.end;
  late String _pharmacistId = widget.existing?.pharmacistId ??
      (widget.pharmacists
              .any((p) => p.id == widget.presetPharmacistId)
          ? widget.presetPharmacistId!
          : _pharmacists.first.id);
  late final _noteCtrl =
      TextEditingController(text: widget.existing?.note ?? '');

  bool get _isNew => widget.existing == null;

  @override
  void dispose() {
    _noteCtrl.dispose();
    super.dispose();
  }

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _day,
      firstDate: DateTime(2020),
      lastDate: DateTime(2035),
    );
    if (picked != null) setState(() => _day = picked);
  }

  Future<void> _pickTime(bool isStart) async {
    final current = isStart ? _start : _end;
    final parts = current.split(':');
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
    final pharmacist =
        _pharmacists.firstWhere((p) => p.id == _pharmacistId);
    Navigator.pop(
      context,
      ShiftEditorResult.save(Shift(
        id: widget.existing?.id ?? '',
        dateKey: Shift.keyFor(_day),
        typeId: _typeId,
        start: _start,
        end: _end,
        pharmacist: pharmacist.fullName,
        pharmacistId: pharmacist.id,
        note: _noteCtrl.text.trim(),
        createdBy: widget.existing?.createdBy ?? widget.currentUid,
      )),
    );
  }

  Future<void> _confirmDelete() async {
    final t = AppText.of(context);
    final typeLabel = _types
        .firstWhere((t) => t.id == widget.existing!.typeId,
            orElse: () => ShiftType.unknown(widget.existing!.typeId))
        .label;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(t.deleteShiftTitle),
        content:
            Text(t.deleteShiftBody(widget.existing!.pharmacist, typeLabel)),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: Text(t.cancel)),
          FilledButton.tonal(
              onPressed: () => Navigator.pop(ctx, true),
              child: Text(t.delete)),
        ],
      ),
    );
    if (confirmed == true && mounted) {
      Navigator.pop(context, ShiftEditorResult.delete(widget.existing!));
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = AppText.of(context);
    return AlertDialog(
      title: Text(_isNew ? t.addShift : t.editShift),
      content: Form(
        key: _formKey,
        child: SizedBox(
          width: 380,
          child: ListView(
            shrinkWrap: true,
            children: [
              OutlinedButton.icon(
                icon: const Icon(Icons.calendar_today, size: 18),
                label: Text(DateFormat('EEE, d MMM yyyy').format(_day)),
                onPressed: _pickDate,
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<String>(
                initialValue: _typeId,
                decoration: InputDecoration(
                    labelText: t.fieldShiftType,
                    border: const OutlineInputBorder()),
                items: [
                  for (final type in _types)
                    DropdownMenuItem(
                      value: type.id,
                      child: Row(children: [
                        Container(
                          width: 12,
                          height: 12,
                          margin: const EdgeInsets.only(right: 8),
                          decoration: BoxDecoration(
                              color: type.color, shape: BoxShape.circle),
                        ),
                        Text([
                          type.label,
                          if (type.description.isNotEmpty) type.description,
                          if (type.start.isNotEmpty)
                            '(${type.start}–${type.end})',
                        ].join(' ')),
                      ]),
                    ),
                ],
                onChanged: (typeId) {
                  if (typeId == null) return;
                  final type = _types.firstWhere((t) => t.id == typeId);
                  setState(() {
                    _typeId = typeId;
                    if (type.start.isNotEmpty) {
                      _start = type.start;
                      _end = type.end;
                    }
                  });
                },
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
              const SizedBox(height: 12),
              DropdownButtonFormField<String>(
                initialValue: _pharmacistId,
                decoration: InputDecoration(
                    labelText: t.fieldPharmacist,
                    border: const OutlineInputBorder()),
                items: [
                  for (final pharmacist in _pharmacists)
                    DropdownMenuItem(
                      value: pharmacist.id,
                      child: Text(pharmacist.displayName,
                          overflow: TextOverflow.ellipsis),
                    ),
                ],
                onChanged: (id) {
                  if (id != null) setState(() => _pharmacistId = id);
                },
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _noteCtrl,
                decoration: InputDecoration(
                  labelText: t.fieldNote,
                  border: const OutlineInputBorder(),
                ),
                maxLines: 2,
              ),
            ],
          ),
        ),
      ),
      actions: [
        if (!_isNew)
          TextButton(
            onPressed: _confirmDelete,
            style: TextButton.styleFrom(
                foregroundColor: Theme.of(context).colorScheme.error),
            child: Text(t.delete),
          ),
        TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(t.cancel)),
        FilledButton(onPressed: _submit, child: Text(t.save)),
      ],
    );
  }
}

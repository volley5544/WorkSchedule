import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../models/shift.dart';

/// Result of the editor: either a shift to save, or a request to delete.
class ShiftEditorResult {
  const ShiftEditorResult.save(this.shift) : delete = false;
  const ShiftEditorResult.delete(this.shift) : delete = true;

  final Shift shift;
  final bool delete;
}

/// Opens the create/edit dialog. Returns null if cancelled.
Future<ShiftEditorResult?> showShiftEditor(
  BuildContext context, {
  required DateTime day,
  Shift? existing,
  required String currentUid,
}) {
  return showDialog<ShiftEditorResult>(
    context: context,
    builder: (_) => _ShiftEditorDialog(
      day: day,
      existing: existing,
      currentUid: currentUid,
    ),
  );
}

class _ShiftEditorDialog extends StatefulWidget {
  const _ShiftEditorDialog({
    required this.day,
    required this.currentUid,
    this.existing,
  });

  final DateTime day;
  final String currentUid;
  final Shift? existing;

  @override
  State<_ShiftEditorDialog> createState() => _ShiftEditorDialogState();
}

class _ShiftEditorDialogState extends State<_ShiftEditorDialog> {
  final _formKey = GlobalKey<FormState>();
  late DateTime _day = widget.existing?.date ?? widget.day;
  late ShiftType _type = widget.existing?.type ?? ShiftType.morning;
  late String _start = widget.existing?.start ?? _type.defaultStart;
  late String _end = widget.existing?.end ?? _type.defaultEnd;
  late final _pharmacistCtrl =
      TextEditingController(text: widget.existing?.pharmacist ?? '');
  late final _noteCtrl =
      TextEditingController(text: widget.existing?.note ?? '');

  bool get _isNew => widget.existing == null;

  @override
  void dispose() {
    _pharmacistCtrl.dispose();
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
    Navigator.pop(
      context,
      ShiftEditorResult.save(Shift(
        id: widget.existing?.id ?? '',
        dateKey: Shift.keyFor(_day),
        type: _type,
        start: _start,
        end: _end,
        pharmacist: _pharmacistCtrl.text.trim(),
        note: _noteCtrl.text.trim(),
        createdBy: widget.existing?.createdBy ?? widget.currentUid,
      )),
    );
  }

  Future<void> _confirmDelete() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete shift?'),
        content: Text(
            'Remove ${widget.existing!.pharmacist}\'s ${widget.existing!.type.label.toLowerCase()} shift?'),
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
    if (confirmed == true && mounted) {
      Navigator.pop(context, ShiftEditorResult.delete(widget.existing!));
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(_isNew ? 'Add shift' : 'Edit shift'),
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
              DropdownButtonFormField<ShiftType>(
                initialValue: _type,
                decoration: const InputDecoration(
                    labelText: 'Shift type', border: OutlineInputBorder()),
                items: [
                  for (final type in ShiftType.values)
                    DropdownMenuItem(
                      value: type,
                      child: Row(children: [
                        Container(
                          width: 12,
                          height: 12,
                          margin: const EdgeInsets.only(right: 8),
                          decoration: BoxDecoration(
                              color: type.color, shape: BoxShape.circle),
                        ),
                        Text(type.label),
                      ]),
                    ),
                ],
                onChanged: (type) {
                  if (type == null) return;
                  setState(() {
                    _type = type;
                    _start = type.defaultStart;
                    _end = type.defaultEnd;
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
              TextFormField(
                controller: _pharmacistCtrl,
                decoration: const InputDecoration(
                  labelText: 'Pharmacist name',
                  border: OutlineInputBorder(),
                ),
                textInputAction: TextInputAction.next,
                validator: (v) => (v == null || v.trim().isEmpty)
                    ? 'Enter the pharmacist\'s name'
                    : null,
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _noteCtrl,
                decoration: const InputDecoration(
                  labelText: 'Note (optional)',
                  border: OutlineInputBorder(),
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
            child: const Text('Delete'),
          ),
        TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel')),
        FilledButton(onPressed: _submit, child: const Text('Save')),
      ],
    );
  }
}

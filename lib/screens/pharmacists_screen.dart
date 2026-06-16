import 'package:flutter/material.dart';

import '../models/app_user.dart';
import '../models/pharmacist.dart';
import '../services/schedule_service.dart';

/// Admin-only screen for managing the pharmacist roster list (name, queue
/// number, optional link to a signed-in account for the "My shifts" view).
class PharmacistsScreen extends StatefulWidget {
  const PharmacistsScreen({super.key, required this.service});

  final ScheduleService service;

  @override
  State<PharmacistsScreen> createState() => _PharmacistsScreenState();
}

class _PharmacistsScreenState extends State<PharmacistsScreen> {
  ScheduleService get service => widget.service;

  /// When true the list is arranged by the table **display order** (showOrder);
  /// when false it's arranged by the **scheduling queue**. Dragging reorders
  /// whichever one is active.
  bool _byDisplay = true;

  Future<void> _edit(
    BuildContext context, {
    required List<AppUser> users,
    required List<String> titles,
    Pharmacist? existing,
    required int nextQueue,
  }) async {
    final result = await showDialog<Pharmacist>(
      context: context,
      builder: (_) => _PharmacistDialog(
          existing: existing,
          users: users,
          titles: titles,
          nextQueue: nextQueue),
    );
    if (result == null || !context.mounted) return;
    try {
      await service.savePharmacist(result);
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not save pharmacist: $e')),
        );
      }
    }
  }

  Future<void> _reorder(
    BuildContext context,
    List<Pharmacist> pharmacists,
    int oldIndex,
    int newIndex,
  ) async {
    // ReorderableListView reports newIndex as the slot before removal.
    if (newIndex > oldIndex) newIndex -= 1;
    if (newIndex == oldIndex) return;
    final reordered = [...pharmacists];
    reordered.insert(newIndex, reordered.removeAt(oldIndex));
    try {
      await service.reorderPharmacists(
        reordered.map((p) => p.id).toList(),
        byDisplay: _byDisplay,
      );
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not reorder pharmacists: $e')),
        );
      }
    }
  }

  Future<void> _delete(BuildContext context, Pharmacist pharmacist) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Remove ${pharmacist.fullName}?'),
        content: const Text(
            'Shifts already on the roster keep the saved name, but the '
            'pharmacist disappears from the roster table and the shift '
            'editor.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancel')),
          FilledButton.tonal(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Remove')),
        ],
      ),
    );
    if (confirmed != true || !context.mounted) return;
    try {
      await service.deletePharmacist(pharmacist.id);
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not remove pharmacist: $e')),
        );
      }
    }
  }

  Future<void> _editTitles(
      BuildContext context, List<String> current) async {
    final result = await showDialog<List<String>>(
      context: context,
      builder: (_) => _TitlesDialog(titles: current),
    );
    if (result == null || !context.mounted) return;
    try {
      await service.saveNameTitles(result);
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not save titles: $e')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<List<AppUser>>(
      stream: service.allUsers(),
      builder: (context, userSnap) {
        final users = userSnap.data ?? const <AppUser>[];
        return StreamBuilder<List<String>>(
          stream: service.nameTitles(),
          builder: (context, titleSnap) {
            final titles =
                titleSnap.data ?? ScheduleService.defaultNameTitles;
            return StreamBuilder<List<Pharmacist>>(
          stream: service.pharmacists(),
          builder: (context, snap) {
            final pharmacists = snap.data ?? const <Pharmacist>[];
            final nextQueue =
                pharmacists.isEmpty ? 1 : pharmacists.last.queue + 1;
            return Scaffold(
              appBar: AppBar(
                title: const Text('Pharmacists'),
                actions: [
                  IconButton(
                    tooltip: 'Edit name titles',
                    icon: const Icon(Icons.badge_outlined),
                    onPressed: () => _editTitles(context, titles),
                  ),
                  const SizedBox(width: 4),
                ],
              ),
              floatingActionButton: FloatingActionButton.extended(
                onPressed: () => _edit(context,
                    users: users, titles: titles, nextQueue: nextQueue),
                icon: const Icon(Icons.person_add),
                label: const Text('Add pharmacist'),
              ),
              body: Builder(builder: (context) {
                if (snap.hasError) {
                  return Center(
                      child:
                          Text('Failed to load pharmacists: ${snap.error}'));
                }
                if (!snap.hasData) {
                  return const Center(child: CircularProgressIndicator());
                }
                if (pharmacists.isEmpty) {
                  return Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.groups,
                            size: 56,
                            color: Theme.of(context).colorScheme.outline),
                        const SizedBox(height: 12),
                        const Text(
                            'No pharmacists yet. Add the work group members '
                            'to build the roster.'),
                      ],
                    ),
                  );
                }
                // Display the list in the active mode's order. Scheduling
                // always uses the queue regardless of this view.
                final displayed = _byDisplay
                    ? ([...pharmacists]..sort(Pharmacist.byShowOrder))
                    : pharmacists;
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 10, 16, 4),
                      child: SegmentedButton<bool>(
                        showSelectedIcon: false,
                        segments: const [
                          ButtonSegment(
                            value: true,
                            icon: Icon(Icons.format_list_numbered, size: 18),
                            label: Text('Display order'),
                          ),
                          ButtonSegment(
                            value: false,
                            icon: Icon(Icons.repeat, size: 18),
                            label: Text('Schedule queue'),
                          ),
                        ],
                        selected: {_byDisplay},
                        onSelectionChanged: (s) =>
                            setState(() => _byDisplay = s.first),
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 0, 16, 0),
                      child: Text(
                        _byDisplay
                            ? 'Drag to set the table display order — used '
                                'everywhere pharmacists are listed.'
                            : 'Drag to set the queue number (เลขที่ Que) — the '
                                'auto-schedule rotation order.',
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                              color: Theme.of(context)
                                  .colorScheme
                                  .onSurfaceVariant,
                            ),
                      ),
                    ),
                    Expanded(
                      child: ReorderableListView.builder(
                        padding: const EdgeInsets.fromLTRB(8, 8, 8, 88),
                        buildDefaultDragHandles: false,
                        itemCount: displayed.length,
                        onReorder: (oldIndex, newIndex) =>
                            _reorder(context, displayed, oldIndex, newIndex),
                        itemBuilder: (context, i) {
                          final pharmacist = displayed[i];
                          final linked = users
                              .where((u) => u.uid == pharmacist.uid)
                              .firstOrNull;
                          final showOrderText = pharmacist.showOrder == 0
                              ? '–'
                              : '${pharmacist.showOrder}';
                          final badge = _byDisplay
                              ? showOrderText
                              : '${pharmacist.queue}';
                          final other = _byDisplay
                              ? 'Que ${pharmacist.queue}'
                              : 'Display $showOrderText';
                          return Column(
                            key: ValueKey(pharmacist.id),
                            children: [
                              ListTile(
                                leading: CircleAvatar(child: Text(badge)),
                                title: Text(pharmacist.displayName,
                                    style: const TextStyle(
                                        fontWeight: FontWeight.w600)),
                                subtitle: Text(
                                  '$other'
                                  '${pharmacist.partTime ? ' · Part-time' : ''}'
                                  ' · ${linked == null ? 'Not linked' : 'Linked to ${linked.email}'}',
                                ),
                                trailing: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    ReorderableDragStartListener(
                                      index: i,
                                      child: const Padding(
                                        padding: EdgeInsets.symmetric(
                                            horizontal: 4),
                                        child: Icon(Icons.drag_handle),
                                      ),
                                    ),
                                    IconButton(
                                      tooltip: 'Edit',
                                      icon: const Icon(Icons.edit_outlined),
                                      onPressed: () => _edit(context,
                                          users: users,
                                          titles: titles,
                                          existing: pharmacist,
                                          nextQueue: nextQueue),
                                    ),
                                    IconButton(
                                      tooltip: 'Remove',
                                      icon: const Icon(Icons.delete_outline),
                                      onPressed: () =>
                                          _delete(context, pharmacist),
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
          },
        );
      },
    );
  }
}

class _PharmacistDialog extends StatefulWidget {
  const _PharmacistDialog({
    this.existing,
    required this.users,
    required this.titles,
    required this.nextQueue,
  });

  final Pharmacist? existing;
  final List<AppUser> users;
  final List<String> titles;
  final int nextQueue;

  @override
  State<_PharmacistDialog> createState() => _PharmacistDialogState();
}

class _PharmacistDialogState extends State<_PharmacistDialog> {
  final _formKey = GlobalKey<FormState>();
  late String _title = widget.existing?.title ?? '';
  late final _nameCtrl =
      TextEditingController(text: widget.existing?.name ?? '');
  late final _lastnameCtrl =
      TextEditingController(text: widget.existing?.lastname ?? '');
  late final _nicknameCtrl =
      TextEditingController(text: widget.existing?.nickname ?? '');
  late final _queueCtrl = TextEditingController(
      text: '${widget.existing?.queue ?? widget.nextQueue}');
  late final _showOrderCtrl =
      TextEditingController(text: '${widget.existing?.showOrder ?? 0}');
  late bool _partTime = widget.existing?.partTime ?? false;
  late String? _uid = widget.existing?.uid;

  bool get _isNew => widget.existing == null;

  @override
  void dispose() {
    _nameCtrl.dispose();
    _lastnameCtrl.dispose();
    _nicknameCtrl.dispose();
    _queueCtrl.dispose();
    _showOrderCtrl.dispose();
    super.dispose();
  }

  void _submit() {
    if (!_formKey.currentState!.validate()) return;
    Navigator.pop(
      context,
      Pharmacist(
        id: widget.existing?.id ?? '',
        name: _nameCtrl.text.trim(),
        title: _title,
        lastname: _lastnameCtrl.text.trim(),
        nickname: _nicknameCtrl.text.trim(),
        queue: int.parse(_queueCtrl.text.trim()),
        showOrder: int.tryParse(_showOrderCtrl.text.trim()) ?? 0,
        partTime: _partTime,
        uid: _uid,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    // Keep a stale uid selectable so editing other fields never silently
    // unlinks an account that has not signed in recently.
    final uids = {for (final u in widget.users) u.uid};
    final hasStaleUid = _uid != null && !uids.contains(_uid);
    return AlertDialog(
      title: Text(_isNew ? 'Add pharmacist' : 'Edit pharmacist'),
      content: Form(
        key: _formKey,
        child: SizedBox(
          width: 360,
          child: ListView(
            shrinkWrap: true,
            children: [
              DropdownButtonFormField<String>(
                initialValue: _title,
                decoration: const InputDecoration(
                  labelText: 'Title (คำนำหน้า)',
                  border: OutlineInputBorder(),
                ),
                items: [
                  const DropdownMenuItem(value: '', child: Text('—')),
                  // Keep a title that was removed from the config selectable
                  // so editing other fields never silently drops it.
                  if (_title.isNotEmpty && !widget.titles.contains(_title))
                    DropdownMenuItem(value: _title, child: Text(_title)),
                  for (final title in widget.titles)
                    DropdownMenuItem(value: title, child: Text(title)),
                ],
                onChanged: (title) =>
                    setState(() => _title = title ?? ''),
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _nameCtrl,
                decoration: const InputDecoration(
                  labelText: 'Name',
                  border: OutlineInputBorder(),
                ),
                validator: (v) => (v == null || v.trim().isEmpty)
                    ? 'Enter the pharmacist\'s name'
                    : null,
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _lastnameCtrl,
                decoration: const InputDecoration(
                  labelText: 'Last name (optional)',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _nicknameCtrl,
                decoration: const InputDecoration(
                  labelText: 'Nickname (optional)',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _queueCtrl,
                decoration: const InputDecoration(
                  labelText: 'Queue number (เลขที่ Que — scheduling order)',
                  border: OutlineInputBorder(),
                ),
                keyboardType: TextInputType.number,
                validator: (v) => int.tryParse(v?.trim() ?? '') == null
                    ? 'Enter a number'
                    : null,
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _showOrderCtrl,
                decoration: const InputDecoration(
                  labelText: 'Table display order (oldest first; 0 = use queue)',
                  helperText: 'Orders the Roster/Original tables only — not the '
                      'scheduling rotation.',
                  helperMaxLines: 2,
                  border: OutlineInputBorder(),
                ),
                keyboardType: TextInputType.number,
                validator: (v) {
                  final t = v?.trim() ?? '';
                  return t.isEmpty || int.tryParse(t) != null
                      ? null
                      : 'Enter a number';
                },
              ),
              const SizedBox(height: 4),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Part-time'),
                subtitle: Text(
                  'Left out of the normal auto-schedule rotation. Only gets '
                  'shifts where added to a shift type\'s custom rotation.',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
                value: _partTime,
                onChanged: (v) => setState(() => _partTime = v),
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<String?>(
                initialValue: _uid,
                decoration: const InputDecoration(
                  labelText: 'Linked account (for "My shifts")',
                  border: OutlineInputBorder(),
                ),
                items: [
                  const DropdownMenuItem(
                      value: null, child: Text('Not linked')),
                  if (hasStaleUid)
                    DropdownMenuItem(
                        value: _uid, child: Text('Unknown account ($_uid)')),
                  for (final user in widget.users)
                    DropdownMenuItem(
                      value: user.uid,
                      child: Text(
                          user.displayName.isEmpty
                              ? user.email
                              : '${user.displayName} (${user.email})',
                          overflow: TextOverflow.ellipsis),
                    ),
                ],
                onChanged: (uid) => setState(() => _uid = uid),
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

/// Edits the configurable list of name titles (คำนำหน้า).
class _TitlesDialog extends StatefulWidget {
  const _TitlesDialog({required this.titles});

  final List<String> titles;

  @override
  State<_TitlesDialog> createState() => _TitlesDialogState();
}

class _TitlesDialogState extends State<_TitlesDialog> {
  late final List<String> _titles = [...widget.titles];
  final _newTitleCtrl = TextEditingController();

  @override
  void dispose() {
    _newTitleCtrl.dispose();
    super.dispose();
  }

  void _add() {
    final title = _newTitleCtrl.text.trim();
    if (title.isEmpty || _titles.contains(title)) return;
    setState(() {
      _titles.add(title);
      _newTitleCtrl.clear();
    });
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Name titles'),
      content: SizedBox(
        width: 320,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Flexible(
              child: ListView(
                shrinkWrap: true,
                children: [
                  for (final title in _titles)
                    ListTile(
                      dense: true,
                      contentPadding:
                          const EdgeInsets.symmetric(horizontal: 8),
                      title: Text(title),
                      trailing: IconButton(
                        tooltip: 'Remove',
                        icon: const Icon(Icons.close, size: 18),
                        onPressed: () =>
                            setState(() => _titles.remove(title)),
                      ),
                    ),
                ],
              ),
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _newTitleCtrl,
                    decoration: const InputDecoration(
                      labelText: 'New title',
                      border: OutlineInputBorder(),
                      isDense: true,
                    ),
                    onSubmitted: (_) => _add(),
                  ),
                ),
                const SizedBox(width: 8),
                IconButton.filledTonal(
                  tooltip: 'Add',
                  icon: const Icon(Icons.add),
                  onPressed: _add,
                ),
              ],
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel')),
        FilledButton(
          onPressed:
              _titles.isEmpty ? null : () => Navigator.pop(context, _titles),
          child: const Text('Save'),
        ),
      ],
    );
  }
}

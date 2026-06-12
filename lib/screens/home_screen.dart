import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../models/app_user.dart';
import '../models/shift.dart';
import '../services/auth_service.dart';
import '../services/schedule_service.dart';
import '../widgets/day_shifts_panel.dart';
import '../widgets/month_calendar.dart';
import '../widgets/shift_editor_dialog.dart';
import 'manage_users_screen.dart';

/// Below this width the layout switches to the mobile (compact) arrangement:
/// dot-calendar on top, selected-day list below.
const _kWideBreakpoint = 840.0;

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key, required this.user, required this.auth});

  final AppUser user;
  final AuthService auth;

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final _service = ScheduleService();
  DateTime _month = DateTime(DateTime.now().year, DateTime.now().month);
  DateTime _selectedDay = DateTime.now();

  bool get _canEdit => widget.user.role.canEdit;

  void _changeMonth(int delta) {
    setState(() {
      _month = DateTime(_month.year, _month.month + delta);
      // Keep selection inside the visible month so the side panel stays relevant.
      if (_selectedDay.year != _month.year ||
          _selectedDay.month != _month.month) {
        final today = DateTime.now();
        _selectedDay =
            (today.year == _month.year && today.month == _month.month)
                ? today
                : DateTime(_month.year, _month.month, 1);
      }
    });
  }

  void _goToToday() {
    setState(() {
      final now = DateTime.now();
      _month = DateTime(now.year, now.month);
      _selectedDay = now;
    });
  }

  Future<void> _openEditor({Shift? existing, DateTime? day}) async {
    final result = await showShiftEditor(
      context,
      day: day ?? _selectedDay,
      existing: existing,
      currentUid: widget.user.uid,
    );
    if (result == null || !mounted) return;
    try {
      if (result.delete) {
        await _service.deleteShift(result.shift.id);
      } else {
        await _service.saveShift(result.shift);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not save shift: $e')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<Map<String, List<Shift>>>(
      stream: _service.shiftsForMonth(_month),
      builder: (context, snap) {
        final shiftsByDay = snap.data ?? const <String, List<Shift>>{};
        final dayShifts =
            shiftsByDay[Shift.keyFor(_selectedDay)] ?? const <Shift>[];
        return LayoutBuilder(builder: (context, constraints) {
          final isWide = constraints.maxWidth >= _kWideBreakpoint;
          return Scaffold(
            appBar: _buildAppBar(context, isWide),
            floatingActionButton: _canEdit && !isWide
                ? FloatingActionButton(
                    onPressed: () => _openEditor(),
                    tooltip: 'Add shift',
                    child: const Icon(Icons.add),
                  )
                : null,
            body: Column(
              children: [
                if (snap.hasError)
                  MaterialBanner(
                    content: Text('Could not load shifts: ${snap.error}'),
                    actions: const [SizedBox.shrink()],
                  ),
                _MonthBar(
                  month: _month,
                  onPrev: () => _changeMonth(-1),
                  onNext: () => _changeMonth(1),
                  onToday: _goToToday,
                ),
                Expanded(
                  child: isWide
                      ? Row(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            Expanded(
                              child: Padding(
                                padding: const EdgeInsets.all(8),
                                child: MonthCalendar(
                                  month: _month,
                                  selectedDay: _selectedDay,
                                  shiftsByDay: shiftsByDay,
                                  onSelectDay: (d) =>
                                      setState(() => _selectedDay = d),
                                  onDoubleTapDay: _canEdit
                                      ? (d) {
                                          setState(() => _selectedDay = d);
                                          _openEditor(day: d);
                                        }
                                      : null,
                                ),
                              ),
                            ),
                            const VerticalDivider(width: 1),
                            SizedBox(
                              width: 320,
                              child: DayShiftsPanel(
                                day: _selectedDay,
                                shifts: dayShifts,
                                canEdit: _canEdit,
                                onAddShift: () => _openEditor(),
                                onEditShift: (s) => _openEditor(existing: s),
                              ),
                            ),
                          ],
                        )
                      : Column(
                          children: [
                            SizedBox(
                              height: 340,
                              child: Padding(
                                padding:
                                    const EdgeInsets.symmetric(horizontal: 4),
                                child: MonthCalendar(
                                  month: _month,
                                  selectedDay: _selectedDay,
                                  shiftsByDay: shiftsByDay,
                                  compact: true,
                                  onSelectDay: (d) =>
                                      setState(() => _selectedDay = d),
                                ),
                              ),
                            ),
                            const Divider(height: 1),
                            Expanded(
                              child: DayShiftsPanel(
                                day: _selectedDay,
                                shifts: dayShifts,
                                canEdit: _canEdit,
                                onAddShift: () => _openEditor(),
                                onEditShift: (s) => _openEditor(existing: s),
                              ),
                            ),
                          ],
                        ),
                ),
              ],
            ),
          );
        });
      },
    );
  }

  AppBar _buildAppBar(BuildContext context, bool isWide) {
    final user = widget.user;
    return AppBar(
      title: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.local_pharmacy),
          const SizedBox(width: 8),
          Flexible(
            child: Text(isWide ? 'Pharmacy Work Schedule' : 'Pharmacy Schedule',
                overflow: TextOverflow.ellipsis),
          ),
        ],
      ),
      actions: [
        Padding(
          padding: const EdgeInsets.only(right: 8),
          child: Center(
            child: Chip(
              visualDensity: VisualDensity.compact,
              label: Text(user.role.label,
                  style: const TextStyle(fontSize: 12)),
            ),
          ),
        ),
        PopupMenuButton<String>(
          tooltip: user.displayName,
          icon: CircleAvatar(
            radius: 16,
            foregroundImage:
                user.photoUrl == null ? null : NetworkImage(user.photoUrl!),
            child: Text(user.displayName.isEmpty
                ? '?'
                : user.displayName.characters.first.toUpperCase()),
          ),
          itemBuilder: (context) => [
            PopupMenuItem(
              enabled: false,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(user.displayName,
                      style: const TextStyle(fontWeight: FontWeight.bold)),
                  Text(user.email,
                      style: Theme.of(context).textTheme.bodySmall),
                ],
              ),
            ),
            const PopupMenuDivider(),
            if (user.role.isAdmin)
              const PopupMenuItem(
                value: 'users',
                child: ListTile(
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  leading: Icon(Icons.manage_accounts),
                  title: Text('Manage users'),
                ),
              ),
            const PopupMenuItem(
              value: 'signout',
              child: ListTile(
                dense: true,
                contentPadding: EdgeInsets.zero,
                leading: Icon(Icons.logout),
                title: Text('Sign out'),
              ),
            ),
          ],
          onSelected: (value) {
            switch (value) {
              case 'users':
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => ManageUsersScreen(
                        service: _service, currentUser: user),
                  ),
                );
              case 'signout':
                widget.auth.signOut();
            }
          },
        ),
        const SizedBox(width: 8),
      ],
    );
  }
}

class _MonthBar extends StatelessWidget {
  const _MonthBar({
    required this.month,
    required this.onPrev,
    required this.onNext,
    required this.onToday,
  });

  final DateTime month;
  final VoidCallback onPrev;
  final VoidCallback onNext;
  final VoidCallback onToday;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 8, 8, 0),
      child: Row(
        children: [
          IconButton(
              onPressed: onPrev,
              tooltip: 'Previous month',
              icon: const Icon(Icons.chevron_left)),
          Expanded(
            child: Center(
              child: Text(
                DateFormat('MMMM yyyy').format(month),
                style: Theme.of(context)
                    .textTheme
                    .titleLarge
                    ?.copyWith(fontWeight: FontWeight.w600),
              ),
            ),
          ),
          TextButton(onPressed: onToday, child: const Text('Today')),
          IconButton(
              onPressed: onNext,
              tooltip: 'Next month',
              icon: const Icon(Icons.chevron_right)),
        ],
      ),
    );
  }
}

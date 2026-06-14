import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../models/app_user.dart';
import '../models/holiday.dart';
import '../models/pharmacist.dart';
import '../models/shift.dart';
import '../models/shift_type.dart';
import '../services/auth_service.dart';
import '../services/schedule_service.dart';
import '../widgets/auto_schedule_dialog.dart';
import '../widgets/day_shifts_panel.dart';
import '../widgets/month_calendar.dart';
import '../widgets/roster_table.dart';
import '../widgets/shift_editor_dialog.dart';
import 'holidays_screen.dart';
import 'manage_users_screen.dart';
import 'pharmacists_screen.dart';
import 'shift_types_screen.dart';

/// Below this width the layout switches to the mobile (compact) arrangement:
/// dot-calendar on top, selected-day list below.
const _kWideBreakpoint = 840.0;

/// The ways to look at the month.
enum _RosterView { mine, day, roster, original }

class HomeScreen extends StatefulWidget {
  const HomeScreen({
    super.key,
    required this.user,
    required this.auth,
    this.onSignIn,
  });

  final AppUser user;
  final AuthService auth;

  /// Shown as a "Sign in" action when browsing as a guest.
  final VoidCallback? onSignIn;

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final _service = ScheduleService();
  DateTime _month = DateTime(DateTime.now().year, DateTime.now().month);
  DateTime _selectedDay = DateTime.now();
  _RosterView _view = _RosterView.day;

  /// Latest config; refreshed by the StreamBuilders in [build].
  List<ShiftType> _types = const [];
  List<Pharmacist> _pharmacists = const [];

  /// Clinic holidays as dateKey → name, for calendar/roster marking.
  Map<String, String> _holidaysByDate = const {};

  // Streams are held as fields rather than created inside build(): a fresh
  // stream on every rebuild makes each StreamBuilder fall back to its
  // waiting/no-data state, which flashed an empty table whenever the user
  // switched tabs. The config streams never change; the month-scoped ones are
  // rebuilt only when [_month] actually changes (see [_setMonth]).
  late final Stream<List<ShiftType>> _typesStream = _service.shiftTypes();
  late final Stream<List<Pharmacist>> _pharmacistsStream = _service
      .pharmacists();
  late final Stream<List<Holiday>> _holidaysStream = _service.holidays();
  late Stream<Map<String, List<Shift>>> _shiftsStream;
  late Stream<Map<String, List<Shift>>> _originalStream;

  @override
  void initState() {
    super.initState();
    _refreshMonthStreams();
  }

  void _refreshMonthStreams() {
    _shiftsStream = _service.shiftsForMonth(_month);
    _originalStream = _service.originalShiftsForMonth(_month);
  }

  bool get _canEdit => !_isGuest && widget.user.role.canEdit;
  bool get _isGuest => widget.user.isGuest;

  /// Moves to [month] and rebuilds the month-scoped streams. [selectedDay]
  /// overrides the auto-chosen in-month selection when given.
  void _setMonth(DateTime month, {DateTime? selectedDay}) {
    setState(() {
      _month = DateTime(month.year, month.month);
      if (selectedDay != null) {
        _selectedDay = selectedDay;
      } else if (_selectedDay.year != _month.year ||
          _selectedDay.month != _month.month) {
        // Keep selection inside the visible month so the side panel stays
        // relevant.
        final today = DateTime.now();
        _selectedDay =
            (today.year == _month.year && today.month == _month.month)
            ? today
            : DateTime(_month.year, _month.month, 1);
      }
      _refreshMonthStreams();
    });
  }

  void _changeMonth(int delta) =>
      _setMonth(DateTime(_month.year, _month.month + delta));

  void _goToToday() {
    final now = DateTime.now();
    _setMonth(now, selectedDay: now);
  }

  Future<void> _openEditor({
    Shift? existing,
    DateTime? day,
    String? presetPharmacistId,
  }) async {
    final isAdmin = widget.user.role.isAdmin;
    if (_types.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            isAdmin
                ? 'No shift types configured yet. Add them under '
                      'avatar menu → Shift types.'
                : 'No shift types configured yet. Ask an admin to set them up.',
          ),
        ),
      );
      return;
    }
    if (_pharmacists.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            isAdmin
                ? 'No pharmacists configured yet. Add them under '
                      'avatar menu → Pharmacists.'
                : 'No pharmacists configured yet. Ask an admin to add them.',
          ),
        ),
      );
      return;
    }
    final result = await showShiftEditor(
      context,
      day: day ?? _selectedDay,
      types: _types,
      pharmacists: _pharmacists,
      presetPharmacistId: presetPharmacistId,
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
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Could not save shift: $e')));
      }
    }
  }

  Future<void> _runAutoSchedule() async {
    final isAdmin = widget.user.role.isAdmin;
    if (_types.isEmpty || _pharmacists.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            isAdmin
                ? 'Configure shift types and pharmacists first '
                      '(avatar menu → Shift types / Pharmacists).'
                : 'Shift types and pharmacists are not configured yet. '
                      'Ask an admin to set them up.',
          ),
        ),
      );
      return;
    }
    final request = await showAutoScheduleDialog(context);
    if (request == null || !mounted) return;
    final messenger = ScaffoldMessenger.of(context);
    messenger.showSnackBar(
      const SnackBar(content: Text('Generating schedule…')),
    );
    try {
      final created = await _service.autoSchedule(
        startMonth: request.startMonth,
        months: request.months,
        types: _types,
        pharmacists: _pharmacists,
        createdBy: widget.user.uid,
        replaceExisting: request.replaceExisting,
      );
      messenger.hideCurrentSnackBar();
      messenger.showSnackBar(
        SnackBar(
          content: Text(
            created == 0
                ? 'Nothing to schedule: the selected months are already '
                      'filled.'
                : 'Auto-scheduled $created shifts.',
          ),
        ),
      );
      if (mounted) {
        final start = DateTime(
          request.startMonth.year,
          request.startMonth.month,
        );
        setState(() => _view = _RosterView.roster);
        _setMonth(start, selectedDay: start);
      }
    } catch (e) {
      messenger.hideCurrentSnackBar();
      messenger.showSnackBar(
        SnackBar(content: Text('Auto schedule failed: $e')),
      );
    }
  }

  void _onRosterCell(
    Pharmacist pharmacist,
    DateTime day,
    List<Shift> cellShifts,
  ) {
    setState(() => _selectedDay = day);
    if (!_canEdit) return;
    if (cellShifts.isEmpty) {
      _openEditor(day: day, presetPharmacistId: pharmacist.id);
    } else if (cellShifts.length == 1) {
      _openEditor(existing: cellShifts.first);
    } else {
      // Several shifts in one cell: let the editor pick which one.
      showDialog<void>(
        context: context,
        builder: (ctx) => SimpleDialog(
          title: Text(
            '${pharmacist.fullName} · ${DateFormat('d MMM').format(day)}',
          ),
          children: [
            for (final shift in cellShifts)
              SimpleDialogOption(
                onPressed: () {
                  Navigator.pop(ctx);
                  _openEditor(existing: shift);
                },
                child: Text('${shift.start}–${shift.end}'),
              ),
            SimpleDialogOption(
              onPressed: () {
                Navigator.pop(ctx);
                _openEditor(day: day, presetPharmacistId: pharmacist.id);
              },
              child: const Row(
                children: [
                  Icon(Icons.add, size: 18),
                  SizedBox(width: 8),
                  Text('Add another shift'),
                ],
              ),
            ),
          ],
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<List<ShiftType>>(
      stream: _typesStream,
      builder: (context, typeSnap) {
        _types = typeSnap.data ?? _types;
        final typesById = {for (final t in _types) t.id: t};
        return StreamBuilder<List<Pharmacist>>(
          stream: _pharmacistsStream,
          builder: (context, pharmacistSnap) {
            _pharmacists = pharmacistSnap.data ?? _pharmacists;
            return StreamBuilder<List<Holiday>>(
              stream: _holidaysStream,
              builder: (context, holidaySnap) {
                final holidayData = holidaySnap.data;
                if (holidayData != null) {
                  _holidaysByDate = {
                    for (final h in holidayData) h.dateKey: h.name,
                  };
                }
                return StreamBuilder<Map<String, List<Shift>>>(
                  stream: _shiftsStream,
                  builder: (context, snap) {
                    final shiftsByDay =
                        snap.data ?? const <String, List<Shift>>{};
                    return LayoutBuilder(
                      builder: (context, constraints) {
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
                                  content: Text(
                                    'Could not load shifts: ${snap.error}',
                                  ),
                                  actions: const [SizedBox.shrink()],
                                ),
                              _MonthBar(
                                month: _month,
                                onPrev: () => _changeMonth(-1),
                                onNext: () => _changeMonth(1),
                                onToday: _goToToday,
                              ),
                              // Horizontally scrollable so the four segments are
                              // never clipped on mid-width windows (the Original
                              // segment used to fall off the right edge).
                              SingleChildScrollView(
                                scrollDirection: Axis.horizontal,
                                padding: const EdgeInsets.fromLTRB(8, 4, 8, 4),
                                child: SegmentedButton<_RosterView>(
                                  showSelectedIcon: false,
                                  segments: [
                                    if (!_isGuest)
                                      ButtonSegment(
                                        value: _RosterView.mine,
                                        icon: const Icon(
                                          Icons.person,
                                          size: 18,
                                        ),
                                        label: isWide
                                            ? const Text('My shifts')
                                            : null,
                                        tooltip: 'My shifts',
                                      ),
                                    ButtonSegment(
                                      value: _RosterView.day,
                                      icon: const Icon(
                                        Icons.calendar_month,
                                        size: 18,
                                      ),
                                      label: isWide
                                          ? const Text('By day')
                                          : null,
                                      tooltip: 'By day',
                                    ),
                                    ButtonSegment(
                                      value: _RosterView.roster,
                                      icon: const Icon(
                                        Icons.table_chart,
                                        size: 18,
                                      ),
                                      label: isWide
                                          ? const Text('Roster')
                                          : null,
                                      tooltip: 'Roster table',
                                    ),
                                    ButtonSegment(
                                      value: _RosterView.original,
                                      icon: const Icon(
                                        Icons.lock_outline,
                                        size: 18,
                                      ),
                                      label: isWide
                                          ? const Text('Original')
                                          : null,
                                      tooltip:
                                          'Original (auto-generated, read-only)',
                                    ),
                                  ],
                                  selected: {_view},
                                  onSelectionChanged: (selection) =>
                                      setState(() => _view = selection.first),
                                ),
                              ),
                              Expanded(
                                child: _buildBody(
                                  context,
                                  isWide,
                                  shiftsByDay,
                                  typesById,
                                ),
                              ),
                            ],
                          ),
                        );
                      },
                    );
                  },
                );
              },
            );
          },
        );
      },
    );
  }

  Widget _buildBody(
    BuildContext context,
    bool isWide,
    Map<String, List<Shift>> shiftsByDay,
    Map<String, ShiftType> typesById,
  ) {
    if (_view == _RosterView.roster) {
      return RosterTable(
        month: _month,
        pharmacists: _pharmacists,
        shiftsByDay: shiftsByDay,
        typesById: typesById,
        holidaysByDate: _holidaysByDate,
        onTapCell: _onRosterCell,
      );
    }

    if (_view == _RosterView.original) {
      // Read-only baseline: no onTapCell, so cells can't be edited. Streamed
      // from its own collection so it stays fixed while the live Roster is
      // swapped around.
      return Column(
        children: [
          MaterialBanner(
            backgroundColor: Theme.of(
              context,
            ).colorScheme.surfaceContainerHighest,
            leading: const Icon(Icons.lock_outline),
            content: const Text(
              'Original auto-generated schedule (read-only). Compare it '
              'with the Roster tab to spot shift exchanges.',
            ),
            actions: const [SizedBox.shrink()],
          ),
          Expanded(
            child: StreamBuilder<Map<String, List<Shift>>>(
              stream: _originalStream,
              builder: (context, snap) {
                final originalByDay =
                    snap.data ?? const <String, List<Shift>>{};
                return RosterTable(
                  month: _month,
                  pharmacists: _pharmacists,
                  shiftsByDay: originalByDay,
                  typesById: typesById,
                  holidaysByDate: _holidaysByDate,
                );
              },
            ),
          ),
        ],
      );
    }

    var visibleShifts = shiftsByDay;
    Widget? banner;
    if (_view == _RosterView.mine) {
      final myIds = _pharmacists
          .where((p) => p.uid == widget.user.uid)
          .map((p) => p.id)
          .toSet();
      if (myIds.isEmpty) {
        banner = MaterialBanner(
          content: const Text(
            'Your account is not linked to a pharmacist yet, so there is '
            'nothing to show here. Ask an admin to link it under '
            'Pharmacists.',
          ),
          leading: const Icon(Icons.link_off),
          actions: const [SizedBox.shrink()],
        );
        visibleShifts = const {};
      } else {
        visibleShifts = {
          for (final entry in shiftsByDay.entries)
            entry.key: entry.value
                .where((s) => myIds.contains(s.pharmacistId))
                .toList(),
        }..removeWhere((_, shifts) => shifts.isEmpty);
      }
    }

    final dayShifts =
        visibleShifts[Shift.keyFor(_selectedDay)] ?? const <Shift>[];

    final calendarAndPanel = isWide
        ? Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.all(8),
                  child: MonthCalendar(
                    month: _month,
                    selectedDay: _selectedDay,
                    shiftsByDay: visibleShifts,
                    typesById: typesById,
                    holidaysByDate: _holidaysByDate,
                    codeOnly: _view == _RosterView.mine,
                    onSelectDay: (d) => setState(() => _selectedDay = d),
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
                  typesById: typesById,
                  canEdit: _canEdit,
                  onAddShift: () => _openEditor(),
                  onEditShift: (s) => _openEditor(existing: s),
                ),
              ),
            ],
          )
        // On phones the calendar + day panel scroll as one page, so the day's
        // shift list is always reachable even on short screens.
        : SingleChildScrollView(
            child: Column(
              children: [
                SizedBox(
                  height: 340,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 4),
                    child: MonthCalendar(
                      month: _month,
                      selectedDay: _selectedDay,
                      shiftsByDay: visibleShifts,
                      typesById: typesById,
                      holidaysByDate: _holidaysByDate,
                      compact: true,
                      codeOnly: _view == _RosterView.mine,
                      onSelectDay: (d) => setState(() => _selectedDay = d),
                    ),
                  ),
                ),
                const Divider(height: 1),
                DayShiftsPanel(
                  day: _selectedDay,
                  shifts: dayShifts,
                  typesById: typesById,
                  canEdit: _canEdit,
                  onAddShift: () => _openEditor(),
                  onEditShift: (s) => _openEditor(existing: s),
                  shrinkWrap: true,
                ),
              ],
            ),
          );

    if (banner == null) return calendarAndPanel;
    return Column(
      children: [
        banner,
        Expanded(child: calendarAndPanel),
      ],
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
            child: Text(
              isWide ? 'Pharmacy Work Schedule' : 'Pharmacy Schedule',
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
      actions: [
        if (_isGuest) ...[
          Center(
            child: FilledButton.tonalIcon(
              onPressed: widget.onSignIn,
              icon: const Icon(Icons.login, size: 18),
              label: const Text('Sign in'),
            ),
          ),
          const SizedBox(width: 12),
        ] else ...[
          if (_canEdit)
            IconButton(
              tooltip: 'Auto schedule',
              icon: const Icon(Icons.auto_awesome),
              onPressed: _runAutoSchedule,
            ),
          Padding(
            padding: const EdgeInsets.only(right: 8),
            child: Center(
              child: Chip(
                visualDensity: VisualDensity.compact,
                label: Text(
                  user.role.label,
                  style: const TextStyle(fontSize: 12),
                ),
              ),
            ),
          ),
          PopupMenuButton<String>(
            tooltip: user.displayName,
            icon: CircleAvatar(
              radius: 16,
              foregroundImage: user.photoUrl == null
                  ? null
                  : NetworkImage(user.photoUrl!),
              // Swallow load failures (e.g. 429 from Google's CDN) so the
              // initial-letter child below stays visible instead.
              onForegroundImageError: user.photoUrl == null ? null : (_, _) {},
              child: Text(
                user.displayName.isEmpty
                    ? '?'
                    : user.displayName.characters.first.toUpperCase(),
              ),
            ),
            itemBuilder: (context) => [
              PopupMenuItem(
                enabled: false,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      user.displayName,
                      style: const TextStyle(fontWeight: FontWeight.bold),
                    ),
                    Text(
                      user.email,
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ],
                ),
              ),
              const PopupMenuDivider(),
              if (user.role.isAdmin) ...[
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
                  value: 'shiftTypes',
                  child: ListTile(
                    dense: true,
                    contentPadding: EdgeInsets.zero,
                    leading: Icon(Icons.tune),
                    title: Text('Shift types'),
                  ),
                ),
                const PopupMenuItem(
                  value: 'pharmacists',
                  child: ListTile(
                    dense: true,
                    contentPadding: EdgeInsets.zero,
                    leading: Icon(Icons.groups),
                    title: Text('Pharmacists'),
                  ),
                ),
              ],
              // Visible to every signed-in user (read-only unless admin).
              const PopupMenuItem(
                value: 'holidays',
                child: ListTile(
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  leading: Icon(Icons.event_busy),
                  title: Text('Holidays'),
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
                        service: _service,
                        currentUser: user,
                      ),
                    ),
                  );
                case 'shiftTypes':
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => ShiftTypesScreen(service: _service),
                    ),
                  );
                case 'pharmacists':
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => PharmacistsScreen(service: _service),
                    ),
                  );
                case 'holidays':
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => HolidaysScreen(
                        service: _service,
                        canManage: user.role.isAdmin,
                      ),
                    ),
                  );
                case 'signout':
                  widget.auth.signOut();
              }
            },
          ),
          const SizedBox(width: 8),
        ],
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
            icon: const Icon(Icons.chevron_left),
          ),
          Expanded(
            child: Center(
              child: Text(
                DateFormat('MMMM yyyy').format(month),
                style: Theme.of(
                  context,
                ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w600),
              ),
            ),
          ),
          TextButton(onPressed: onToday, child: const Text('Today')),
          IconButton(
            onPressed: onNext,
            tooltip: 'Next month',
            icon: const Icon(Icons.chevron_right),
          ),
        ],
      ),
    );
  }
}

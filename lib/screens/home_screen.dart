import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../l10n/app_text.dart';
import '../models/app_user.dart';
import '../models/holiday.dart';
import '../models/pharmacist.dart';
import '../models/shift.dart';
import '../models/shift_type.dart';
import '../services/auth_service.dart';
import '../services/report_export.dart';
import '../services/schedule_service.dart';
import '../widgets/auto_schedule_dialog.dart';
import '../widgets/day_shifts_panel.dart';
import '../widgets/export_report_dialog.dart';
import '../widgets/month_calendar.dart';
import '../widgets/roster_table.dart';
import '../widgets/settings_dialog.dart';
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
    final t = AppText.of(context);
    if (_types.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content:
              Text(isAdmin ? t.noShiftTypesAdmin : t.noShiftTypesUser),
        ),
      );
      return;
    }
    if (_pharmacists.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content:
              Text(isAdmin ? t.noPharmacistsAdmin : t.noPharmacistsUser),
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
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(AppText.of(context).couldNotSaveShift(e))),
        );
      }
    }
  }

  Future<void> _runAutoSchedule() async {
    final isAdmin = widget.user.role.isAdmin;
    final t = AppText.of(context);
    if (_types.isEmpty || _pharmacists.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content:
              Text(isAdmin ? t.configureFirstAdmin : t.configureFirstUser),
        ),
      );
      return;
    }
    final request = await showAutoScheduleDialog(context);
    if (request == null || !mounted) return;
    final messenger = ScaffoldMessenger.of(context);
    messenger.showSnackBar(
      SnackBar(content: Text(t.generatingSchedule)),
    );
    try {
      final created = await _service.autoSchedule(
        startMonth: request.startMonth,
        months: request.months,
        types: _types,
        pharmacists: _pharmacists,
        createdBy: widget.user.uid,
        holidayKeys: _holidaysByDate.keys.toSet(),
        replaceExisting: request.replaceExisting,
      );
      messenger.hideCurrentSnackBar();
      messenger.showSnackBar(
        SnackBar(
          content: Text(
            created == 0 ? t.nothingToSchedule : t.autoScheduledN(created),
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
        SnackBar(content: Text(t.autoScheduleFailed(e))),
      );
    }
  }

  /// Exports a chosen month range as an Excel report (per-month Roster matrix +
  /// summary) and triggers a download. The user picks the range and the data
  /// source (live roster vs the read-only Original baseline). Editors/admins.
  Future<void> _exportReport() async {
    final t = AppText.of(context);
    final isAdmin = widget.user.role.isAdmin;
    if (_types.isEmpty || _pharmacists.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content:
              Text(isAdmin ? t.configureFirstAdmin : t.configureFirstUser),
        ),
      );
      return;
    }
    final request =
        await showExportReportDialog(context, initialMonth: _month);
    if (request == null || !mounted) return;
    final messenger = ScaffoldMessenger.of(context);
    messenger.showSnackBar(SnackBar(content: Text(t.exportingReport)));
    try {
      // The home screen only streams the visible month, so fetch the whole
      // requested range (from the chosen collection) just for the export.
      final shiftsByDay = await _service.fetchShiftsRange(
        startMonth: request.startMonth,
        months: request.months,
        original: request.useOriginal,
      );
      final fileName = await ReportExport.download(
        startMonth: request.startMonth,
        months: request.months,
        pharmacists: _pharmacists,
        types: _types,
        shiftsByDay: shiftsByDay,
        holidaysByDate: _holidaysByDate,
        useOriginal: request.useOriginal,
      );
      messenger.hideCurrentSnackBar();
      messenger.showSnackBar(
        SnackBar(content: Text(t.reportExported(fileName))),
      );
    } catch (e) {
      messenger.hideCurrentSnackBar();
      messenger.showSnackBar(
        SnackBar(content: Text(t.reportExportFailed(e))),
      );
    }
  }

  /// One-time admin action: seed the May 2026 starting roster from the
  /// transcribed spreadsheet. Replaces any existing May 2026 shifts.
  Future<void> _importMay2026(AppUser user) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Import May 2026 roster'),
        content: const Text(
          'This writes the May 2026 (BE 2569) roster to the live schedule '
          'and the Original baseline, replacing any existing May 2026 shifts. '
          'Continue?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Import'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    final messenger = ScaffoldMessenger.of(context);
    messenger.showSnackBar(
      const SnackBar(content: Text('Importing May 2026…')),
    );
    try {
      final result = await _service.importMay2026(createdBy: user.uid);
      messenger.hideCurrentSnackBar();
      if (!mounted) return;
      await showDialog<void>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('May 2026 imported'),
          content: Text(
            'Created ${result.created} shifts.'
            '${result.warnings.isEmpty ? '' : '\n\nWarnings:\n• ${result.warnings.join('\n• ')}'}',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('OK'),
            ),
          ],
        ),
      );
      if (mounted) {
        setState(() => _view = _RosterView.roster);
        final start = DateTime(2026, 5);
        _setMonth(start, selectedDay: start);
      }
    } catch (e) {
      messenger.hideCurrentSnackBar();
      messenger.showSnackBar(SnackBar(content: Text('Import failed: $e')));
    }
  }

  /// Admin action: snapshot the current month's live Roster into the read-only
  /// Original baseline (replacing that month's Original).
  Future<void> _copyMonthToOriginal() async {
    final monthLabel = DateFormat('MMMM yyyy').format(_month);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Copy roster → Original'),
        content: Text(
          'Copy the current $monthLabel roster into the Original baseline, '
          'replacing the existing Original for $monthLabel? This does not '
          'change the editable roster.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Copy'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    final messenger = ScaffoldMessenger.of(context);
    messenger.showSnackBar(const SnackBar(content: Text('Copying…')));
    try {
      final copied = await _service.copyMonthToOriginal(_month);
      messenger.hideCurrentSnackBar();
      messenger.showSnackBar(
        SnackBar(content: Text('Copied $copied shifts to Original ($monthLabel).')),
      );
    } catch (e) {
      messenger.hideCurrentSnackBar();
      messenger.showSnackBar(SnackBar(content: Text('Copy failed: $e')));
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
      return;
    }
    // One or more existing shifts: let the user pick which to edit, or add
    // another — so a pharmacist can hold a second shift that day (e.g. after a
    // swap they end up on both morning and night).
    String typeLabel(Shift s) {
      for (final t in _types) {
        if (t.id == s.typeId) return t.label;
      }
      return s.typeId.isEmpty ? '?' : s.typeId;
    }

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
              child: Text('${typeLabel(shift)} · ${shift.start}–${shift.end}'),
            ),
          SimpleDialogOption(
            onPressed: () {
              Navigator.pop(ctx);
              _openEditor(day: day, presetPharmacistId: pharmacist.id);
            },
            child: Row(
              children: [
                const Icon(Icons.add, size: 18),
                const SizedBox(width: 8),
                Text(AppText.of(context).addAnotherShift),
              ],
            ),
          ),
        ],
      ),
    );
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
                        final t = AppText.of(context);
                        return Scaffold(
                          appBar: _buildAppBar(context, isWide),
                          floatingActionButton: _canEdit && !isWide
                              ? FloatingActionButton(
                                  onPressed: () => _openEditor(),
                                  tooltip: t.addShift,
                                  child: const Icon(Icons.add),
                                )
                              : null,
                          body: Column(
                            children: [
                              if (snap.hasError)
                                MaterialBanner(
                                  content: Text(
                                    t.couldNotLoadShifts(snap.error ?? ''),
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
                                        label:
                                            isWide ? Text(t.viewMine) : null,
                                        tooltip: t.viewMine,
                                      ),
                                    ButtonSegment(
                                      value: _RosterView.day,
                                      icon: const Icon(
                                        Icons.calendar_month,
                                        size: 18,
                                      ),
                                      label: isWide ? Text(t.viewDay) : null,
                                      tooltip: t.viewDay,
                                    ),
                                    ButtonSegment(
                                      value: _RosterView.roster,
                                      icon: const Icon(
                                        Icons.table_chart,
                                        size: 18,
                                      ),
                                      label:
                                          isWide ? Text(t.viewRoster) : null,
                                      tooltip: t.viewRosterTooltip,
                                    ),
                                    ButtonSegment(
                                      value: _RosterView.original,
                                      icon: const Icon(
                                        Icons.lock_outline,
                                        size: 18,
                                      ),
                                      label: isWide
                                          ? Text(t.viewOriginal)
                                          : null,
                                      tooltip: t.viewOriginalTooltip,
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
    final t = AppText.of(context);
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
            content: Text(t.originalBanner),
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
          content: Text(t.myShiftsNotLinked),
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
    final t = AppText.of(context);
    return AppBar(
      title: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.local_pharmacy),
          const SizedBox(width: 8),
          Flexible(
            child: Text(
              isWide ? t.appTitle : t.appTitleShort,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
      actions: [
        if (_isGuest) ...[
          IconButton(
            tooltip: t.settingsTitle,
            icon: const Icon(Icons.settings_outlined),
            onPressed: () => showSettingsDialog(context),
          ),
          Center(
            child: FilledButton.tonalIcon(
              onPressed: widget.onSignIn,
              icon: const Icon(Icons.login, size: 18),
              label: Text(t.signIn),
            ),
          ),
          const SizedBox(width: 12),
        ] else ...[
          if (_canEdit) ...[
            IconButton(
              tooltip: t.exportReport,
              icon: const Icon(Icons.file_download_outlined),
              onPressed: _exportReport,
            ),
            IconButton(
              tooltip: t.autoSchedule,
              icon: const Icon(Icons.auto_awesome),
              onPressed: _runAutoSchedule,
            ),
          ],
          Padding(
            padding: const EdgeInsets.only(right: 8),
            child: Center(
              child: Chip(
                visualDensity: VisualDensity.compact,
                label: Text(
                  t.roleLabel(user.role),
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
                PopupMenuItem(
                  value: 'users',
                  child: ListTile(
                    dense: true,
                    contentPadding: EdgeInsets.zero,
                    leading: const Icon(Icons.manage_accounts),
                    title: Text(t.menuManageUsers),
                  ),
                ),
                PopupMenuItem(
                  value: 'shiftTypes',
                  child: ListTile(
                    dense: true,
                    contentPadding: EdgeInsets.zero,
                    leading: const Icon(Icons.tune),
                    title: Text(t.menuShiftTypes),
                  ),
                ),
                PopupMenuItem(
                  value: 'pharmacists',
                  child: ListTile(
                    dense: true,
                    contentPadding: EdgeInsets.zero,
                    leading: const Icon(Icons.groups),
                    title: Text(t.menuPharmacists),
                  ),
                ),
                // One-time seed of the May 2026 starting roster (throwaway).
                const PopupMenuItem(
                  value: 'importMay2026',
                  child: ListTile(
                    dense: true,
                    contentPadding: EdgeInsets.zero,
                    leading: Icon(Icons.file_download),
                    title: Text('Import May 2026 (one-time)'),
                  ),
                ),
                const PopupMenuItem(
                  value: 'copyToOriginal',
                  child: ListTile(
                    dense: true,
                    contentPadding: EdgeInsets.zero,
                    leading: Icon(Icons.content_copy),
                    title: Text('Copy roster → Original (this month)'),
                  ),
                ),
              ],
              // Visible to every signed-in user (read-only unless admin).
              PopupMenuItem(
                value: 'holidays',
                child: ListTile(
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(Icons.event_busy),
                  title: Text(t.menuHolidays),
                ),
              ),
              PopupMenuItem(
                value: 'settings',
                child: ListTile(
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(Icons.settings_outlined),
                  title: Text(t.menuSettings),
                ),
              ),
              PopupMenuItem(
                value: 'signout',
                child: ListTile(
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(Icons.logout),
                  title: Text(t.signOut),
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
                      builder: (_) => ShiftTypesScreen(
                        service: _service,
                        pharmacists: _pharmacists,
                      ),
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
                case 'importMay2026':
                  _importMay2026(user);
                case 'copyToOriginal':
                  _copyMonthToOriginal();
                case 'settings':
                  showSettingsDialog(context);
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
    final t = AppText.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 8, 8, 0),
      child: Row(
        children: [
          IconButton(
            onPressed: onPrev,
            tooltip: t.previousMonth,
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
          TextButton(onPressed: onToday, child: Text(t.today)),
          IconButton(
            onPressed: onNext,
            tooltip: t.nextMonth,
            icon: const Icon(Icons.chevron_right),
          ),
        ],
      ),
    );
  }
}

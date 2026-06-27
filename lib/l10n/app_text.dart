import 'package:flutter/widgets.dart';

import '../models/app_user.dart';

/// Bilingual UI strings (Thai / English). Resolve with `AppText.of(context)`,
/// which reads the active locale set on the root `MaterialApp`. Thai is the
/// default. Admin config dialogs are not yet translated (tracked as follow-up).
class AppText {
  const AppText(this.th);

  /// Whether the active language is Thai (else English).
  final bool th;

  static AppText of(BuildContext context) =>
      AppText(Localizations.localeOf(context).languageCode == 'th');

  String _p(String thai, String english) => th ? thai : english;

  // App / common
  String get appTitle => _p('ตารางเวรเภสัชกร', 'Pharmacy Work Schedule');
  String get appTitleShort => _p('ตารางเวร', 'Pharmacy Schedule');
  String get cancel => _p('ยกเลิก', 'Cancel');
  String get save => _p('บันทึก', 'Save');
  String get delete => _p('ลบ', 'Delete');
  String get remove => _p('นำออก', 'Remove');
  String get add => _p('เพิ่ม', 'Add');
  String get done => _p('เสร็จสิ้น', 'Done');
  String get edit => _p('แก้ไข', 'Edit');
  String get signIn => _p('เข้าสู่ระบบ', 'Sign in');
  String get signOut => _p('ออกจากระบบ', 'Sign out');

  // Roles
  String get roleViewer => _p('ผู้ชม', 'Viewer');
  String get roleEditor => _p('ผู้แก้ไข', 'Editor');
  String get roleAdmin => _p('ผู้ดูแล', 'Admin');
  String get guest => _p('ผู้เยี่ยมชม', 'Guest');

  String roleLabel(UserRole role) => switch (role) {
        UserRole.viewer => roleViewer,
        UserRole.editor => roleEditor,
        UserRole.admin => roleAdmin,
      };

  // Login
  String get loginSubtitle => _p(
        'ตารางเวรสำหรับเภสัชกรโรงพยาบาล\nเข้าสู่ระบบด้วยบัญชี Google เพื่อดำเนินการต่อ',
        'Shift roster for hospital pharmacists.\nSign in with your Google account to continue.',
      );
  String get signingIn => _p('กำลังเข้าสู่ระบบ…', 'Signing in…');
  String get signInWithGoogle =>
      _p('เข้าสู่ระบบด้วย Google', 'Sign in with Google');
  String get continueWithoutSignIn =>
      _p('ดูโดยไม่เข้าสู่ระบบ', 'Continue without signing in');
  String get signInFailed => _p('เข้าสู่ระบบไม่สำเร็จ', 'Sign-in failed.');
  String get newAccountNote => _p(
        'บัญชีใหม่จะเริ่มเป็นผู้ชม โปรดขอสิทธิ์ผู้แก้ไขจากผู้ดูแล',
        'New accounts start as Viewer. Ask an admin to grant Editor access.',
      );

  // Home — views
  String get viewMine => _p('เวรของฉัน', 'My shifts');
  String get viewDay => _p('รายวัน', 'By day');
  String get viewRoster => _p('ตารางเวร', 'Roster');
  String get viewOriginal => _p('ต้นฉบับ', 'Original');
  String get viewRosterTooltip => _p('ตารางเวร', 'Roster table');
  String get viewOriginalTooltip => _p(
        'ต้นฉบับ (สร้างอัตโนมัติ อ่านอย่างเดียว)',
        'Original (auto-generated, read-only)',
      );

  // Home — app bar / menu
  String get autoSchedule => _p('จัดเวรอัตโนมัติ', 'Auto schedule');
  String get menuManageUsers => _p('จัดการผู้ใช้', 'Manage users');
  String get menuShiftTypes => _p('ประเภทเวร', 'Shift types');
  String get menuPharmacists => _p('เภสัชกร', 'Pharmacists');
  String get menuHolidays => _p('วันหยุด', 'Holidays');
  String get menuSettings => _p('ตั้งค่า', 'Settings');

  // Month bar
  String get previousMonth => _p('เดือนก่อนหน้า', 'Previous month');
  String get nextMonth => _p('เดือนถัดไป', 'Next month');
  String get today => _p('วันนี้', 'Today');

  // Shifts / editor
  String get addShift => _p('เพิ่มเวร', 'Add shift');
  String get addAnotherShift => _p('เพิ่มเวรอีกหนึ่ง', 'Add another shift');
  String get editShift => _p('แก้ไขเวร', 'Edit shift');
  String get fieldShiftType => _p('ประเภทเวร', 'Shift type');
  String get fieldPharmacist => _p('เภสัชกร', 'Pharmacist');
  String get fieldNote => _p('หมายเหตุ (ไม่บังคับ)', 'Note (optional)');
  String get deleteShiftTitle => _p('ลบเวรนี้?', 'Delete shift?');
  String deleteShiftBody(String name, String type) => _p(
        'นำเวร "$type" ของ $name ออกหรือไม่?',
        'Remove $name\'s "$type" shift?',
      );
  String get noShiftsScheduled => _p('ไม่มีเวรในวันนี้', 'No shifts scheduled.');

  // Roster table
  String get pharmacistColumn => _p('เภสัชกร', 'Pharmacist');
  String get noPharmacistsConfigured => _p(
        'ยังไม่มีเภสัชกร\nผู้ดูแลเพิ่มได้ที่เมนูโปรไฟล์ → เภสัชกร',
        'No pharmacists configured yet.\n'
            'Admins can add them under avatar menu → Pharmacists.',
      );

  // Roster conflict highlights (a pharmacist's day flagged for review)
  String get conflictTitle => _p('ควรตรวจสอบ', 'Needs review');
  String get conflictTooManyShifts => _p(
        'เกิน 2 เวรต่อวัน (วันธรรมดานับงาน 08:30–16:30 ด้วย)',
        'More than 2 duties in a day (weekday 08:30–16:30 work counts)',
      );
  String get conflictTooLong => _p(
        'ทำงานต่อเนื่องเกิน 18 ชั่วโมง',
        'More than 18h continuous duty',
      );
  String get conflictOverlap =>
      _p('เวลาเวรซ้อนทับกัน', 'Shift times overlap');

  // My shifts banner
  String get myShiftsNotLinked => _p(
        'บัญชีของคุณยังไม่ได้เชื่อมกับเภสัชกร จึงยังไม่มีเวรแสดง '
            'โปรดให้ผู้ดูแลเชื่อมบัญชีในหน้าเภสัชกร',
        'Your account is not linked to a pharmacist yet, so there is '
            'nothing to show here. Ask an admin to link it under Pharmacists.',
      );
  String get originalBanner => _p(
        'ตารางต้นฉบับที่สร้างอัตโนมัติ (อ่านอย่างเดียว) '
            'เทียบกับแท็บตารางเวรเพื่อดูการแลกเวร',
        'Original auto-generated schedule (read-only). Compare it '
            'with the Roster tab to spot shift exchanges.',
      );

  // Snackbars / errors
  String couldNotLoadShifts(Object e) =>
      _p('โหลดเวรไม่สำเร็จ: $e', 'Could not load shifts: $e');
  String couldNotSaveShift(Object e) =>
      _p('บันทึกเวรไม่สำเร็จ: $e', 'Could not save shift: $e');
  String get noShiftTypesAdmin => _p(
        'ยังไม่ได้ตั้งค่าประเภทเวร เพิ่มได้ที่เมนูโปรไฟล์ → ประเภทเวร',
        'No shift types configured yet. Add them under avatar menu → Shift types.',
      );
  String get noShiftTypesUser => _p(
        'ยังไม่ได้ตั้งค่าประเภทเวร โปรดให้ผู้ดูแลตั้งค่า',
        'No shift types configured yet. Ask an admin to set them up.',
      );
  String get noPharmacistsAdmin => _p(
        'ยังไม่มีเภสัชกร เพิ่มได้ที่เมนูโปรไฟล์ → เภสัชกร',
        'No pharmacists configured yet. Add them under avatar menu → Pharmacists.',
      );
  String get noPharmacistsUser => _p(
        'ยังไม่มีเภสัชกร โปรดให้ผู้ดูแลเพิ่ม',
        'No pharmacists configured yet. Ask an admin to add them.',
      );
  String get configureFirstAdmin => _p(
        'โปรดตั้งค่าประเภทเวรและเภสัชกรก่อน (เมนูโปรไฟล์ → ประเภทเวร / เภสัชกร)',
        'Configure shift types and pharmacists first '
            '(avatar menu → Shift types / Pharmacists).',
      );
  String get configureFirstUser => _p(
        'ยังไม่ได้ตั้งค่าประเภทเวรและเภสัชกร โปรดให้ผู้ดูแลตั้งค่า',
        'Shift types and pharmacists are not configured yet. '
            'Ask an admin to set them up.',
      );
  String get generatingSchedule => _p('กำลังสร้างตารางเวร…', 'Generating schedule…');
  String get nothingToSchedule => _p(
        'ไม่มีอะไรให้จัด: เดือนที่เลือกมีเวรครบแล้ว',
        'Nothing to schedule: the selected months are already filled.',
      );
  String autoScheduledN(int n) =>
      _p('จัดเวรอัตโนมัติแล้ว $n เวร', 'Auto-scheduled $n shifts.');
  String autoScheduleFailed(Object e) =>
      _p('จัดเวรอัตโนมัติไม่สำเร็จ: $e', 'Auto schedule failed: $e');

  // HR report export
  String get exportReport => _p('ส่งออกรายงาน (Excel)', 'Export report (Excel)');
  String get exportingReport => _p('กำลังส่งออกรายงาน…', 'Exporting report…');
  String reportExported(String fileName) =>
      _p('ส่งออกแล้ว: $fileName', 'Exported $fileName');
  String reportExportFailed(Object e) =>
      _p('ส่งออกรายงานไม่สำเร็จ: $e', 'Export failed: $e');
  String get monthsToExport =>
      _p('จำนวนเดือนที่ส่งออก', 'Months to export');
  String get exportSource => _p('แหล่งข้อมูล', 'Data source');
  String get exportSourceLive => _p('ตารางเวรปัจจุบัน', 'Live roster');
  String get exportSourceOriginal => _p('ต้นฉบับ', 'Original');
  String get exportSourceLiveHelp => _p(
        'ตารางเวรที่ใช้งานจริง รวมการแลกเวร',
        'The working roster, including shift swaps.',
      );
  String get exportSourceOriginalHelp => _p(
        'ต้นฉบับที่สร้างอัตโนมัติ ก่อนการแลกเวร',
        'The auto-generated baseline, before any swaps.',
      );
  String get exportAction => _p('ส่งออก', 'Export');

  // Auto-schedule dialog
  String get startMonth => _p('เดือนเริ่มต้น', 'Start month');
  String get monthsToFill => _p('จำนวนเดือนที่จะจัด', 'Months to fill');
  String monthCount(int m) =>
      th ? '$m เดือน' : '$m month${m == 1 ? '' : 's'}';
  String get regenerateExisting =>
      _p('สร้างเดือนที่มีอยู่ใหม่', 'Regenerate existing months');
  String get regenerateOn => _p(
        'ลบเวรทั้งหมดในเดือนที่เลือกแล้วจัดใหม่ทั้งหมด',
        'All shifts in the selected months are deleted and rescheduled from scratch.',
      );
  String get regenerateOff => _p(
        'คงเวรเดิมไว้ เติมเฉพาะช่องที่ว่าง',
        'Existing shifts are kept; only empty slots are filled.',
      );
  String get generate => _p('สร้าง', 'Generate');
  String get autoScheduleHelp => _p(
        'แต่ละประเภทเวรหมุนเวียนแยกกัน โดยมีลำดับแยกสำหรับวันธรรมดา '
            'วันหยุดสุดสัปดาห์ และวันหยุดนักขัตฤกษ์ ต่อเนื่องจากเดือนก่อนหน้า '
            'วันหยุดถือเป็นวันไม่ทำงาน (จัดเฉพาะประเภทที่ตั้ง "ทำงานวันหยุด") '
            'จะไม่จัดเวรที่เวลาทับซ้อนให้คนเดียวกัน และเคารพลำดับเฉพาะของแต่ละประเภท',
        'Each shift type rotates independently, with a separate turn '
            'order for weekdays, weekends and holidays — continuing from the '
            'month before the start month. Holidays are treated as '
            'non-working days (only shift types marked "runs on holidays" '
            'are scheduled). A pharmacist is never given two overlapping '
            'shifts on the same day. Custom per-type rotations (set under '
            'Shift types) are respected.',
      );

  // Settings
  String get settingsTitle => _p('ตั้งค่า', 'Settings');
  String get language => _p('ภาษา', 'Language');
  String get languageThai => 'ไทย';
  String get languageEnglish => 'English';
  String get theme => _p('ธีม', 'Theme');
  String get themeSystem => _p('ตามอุปกรณ์', 'Follow device');
  String get themeLight => _p('สว่าง', 'Light');
  String get themeDark => _p('มืด', 'Dark');

  // Misc shell
  String get profileErrorTitle =>
      _p('โหลดโปรไฟล์ไม่สำเร็จ', 'Could not load your profile');
  String overflowMore(int n) => _p('+$n เพิ่ม', '+$n more');

  /// Short weekday names, Monday-first, for the calendar/roster headers.
  List<String> get weekdaysShort => th
      ? const ['จ', 'อ', 'พ', 'พฤ', 'ศ', 'ส', 'อา']
      : const ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];

  /// Minimal weekday labels for the compact (phone) calendar header.
  List<String> get weekdaysMin => th
      ? const ['จ', 'อ', 'พ', 'พฤ', 'ศ', 'ส', 'อา']
      : const ['M', 'T', 'W', 'T', 'F', 'S', 'S'];
}

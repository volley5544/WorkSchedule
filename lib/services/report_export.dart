import 'dart:typed_data';

import 'package:excel/excel.dart';
import 'package:file_saver/file_saver.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../models/pharmacist.dart';
import '../models/shift.dart';
import '../models/shift_type.dart';

/// Builds and downloads an HR roster report as a real `.xlsx` file, covering
/// one or more months.
///
/// For **each** month in the range the workbook gets two sheets, both fed from
/// the same data the Roster table shows:
///   * **Roster** — the pharmacist × day matrix, with shift-type codes in the
///     cells (tinted in each type's colour) and weekend/holiday columns shaded.
///   * **Summary** — one row per pharmacist with a count of each shift type,
///     total shifts, and total hours (the figures HR uses for duty pay).
///
/// The caller chooses the data source (the live roster or the read-only
/// Original baseline) by passing in the corresponding shifts.
///
/// Generation is pure (see [buildWorkbook]) so it can be unit-tested; the I/O
/// of triggering the browser download / native save lives in [download].
class ReportExport {
  /// Hours a shift lasts, handling the overnight case: when [end] is at or
  /// before [start] the shift crosses midnight (e.g. ด 23:30→08:30 = 9h).
  static double shiftHours(String start, String end) {
    if (start.trim().isEmpty || end.trim().isEmpty) return 0;
    int mins(String hhmm) {
      final parts = hhmm.split(':');
      if (parts.isEmpty || parts.first.isEmpty) return 0;
      final h = int.tryParse(parts[0]) ?? 0;
      final m = int.tryParse(parts.length > 1 ? parts[1] : '0') ?? 0;
      return h * 60 + m;
    }

    var diff = mins(end) - mins(start);
    if (diff <= 0) diff += 24 * 60;
    return diff / 60.0;
  }

  /// A light tint of [c] (blended toward white) for cell fills, so the bold
  /// code text stays readable — mirrors the ~18% tint used on screen.
  static ExcelColor _tint(Color c, [double alpha = 0.22]) {
    final argb = c.toARGB32();
    int blend(int channel) => (channel * alpha + 255 * (1 - alpha)).round();
    final r = blend((argb >> 16) & 0xFF);
    final g = blend((argb >> 8) & 0xFF);
    final b = blend(argb & 0xFF);
    String h(int v) => v.toRadixString(16).padLeft(2, '0');
    return ExcelColor.fromHexString('FF${h(r)}${h(g)}${h(b)}'.toUpperCase());
  }

  /// Builds the report workbook bytes covering [months] (one Roster + Summary
  /// sheet pair per month, in order). Pure: no I/O.
  static Uint8List buildWorkbook({
    required List<DateTime> months,
    required List<Pharmacist> pharmacists,
    required List<ShiftType> types,
    required Map<String, List<Shift>> shiftsByDay,
    Map<String, String> holidaysByDate = const {},
  }) {
    final excel = Excel.createExcel();
    final people = [...pharmacists]..sort(Pharmacist.byShowOrder);
    final orderedTypes = [...types]
      ..sort((a, b) => a.sortOrder.compareTo(b.sortOrder));
    final typesById = {for (final t in types) t.id: t};

    // (pharmacistId|dateKey) → shifts in that cell, earliest first. Spans the
    // whole range; each month's sheet reads only its own days.
    final byCell = <String, List<Shift>>{};
    for (final dayShifts in shiftsByDay.values) {
      for (final s in dayShifts) {
        byCell.putIfAbsent('${s.pharmacistId}|${s.dateKey}', () => []).add(s);
      }
    }
    for (final list in byCell.values) {
      list.sort(Shift.byStartTime);
    }

    // With a single month the sheets keep plain names; for a range each pair is
    // suffixed with the month so they stay unique and self-labelling.
    final single = months.length <= 1;
    String? firstSheet;
    for (final month in months) {
      final monthLabel = DateFormat('MMMM yyyy').format(month);
      final suffix = single ? '' : ' ${DateFormat('MMM yy').format(month)}';
      final rosterName = 'Roster$suffix';
      _buildRosterSheet(
        excel[rosterName],
        month: month,
        monthLabel: monthLabel,
        daysInMonth: DateTime(month.year, month.month + 1, 0).day,
        people: people,
        typesById: typesById,
        byCell: byCell,
        holidaysByDate: holidaysByDate,
      );
      _buildSummarySheet(
        excel['Summary$suffix'],
        month: month,
        monthLabel: monthLabel,
        people: people,
        orderedTypes: orderedTypes,
        byCell: byCell,
      );
      firstSheet ??= rosterName;
    }

    // Excel.createExcel() seeds a placeholder 'Sheet1'; drop it now that our
    // named sheets exist, and open the workbook on the first Roster sheet.
    excel.delete('Sheet1');
    if (firstSheet != null) excel.setDefaultSheet(firstSheet);
    final bytes = excel.encode();
    return Uint8List.fromList(bytes ?? const []);
  }

  static void _buildRosterSheet(
    Sheet sheet, {
    required DateTime month,
    required String monthLabel,
    required int daysInMonth,
    required List<Pharmacist> people,
    required Map<String, ShiftType> typesById,
    required Map<String, List<Shift>> byCell,
    required Map<String, String> holidaysByDate,
  }) {
    CellIndex at(int col, int row) =>
        CellIndex.indexByColumnRow(columnIndex: col, rowIndex: row);
    final headerFill = ExcelColor.fromHexString('FFE8EAF0');
    final weekendFill = ExcelColor.fromHexString('FFE0E4EA');
    final holidayFill = ExcelColor.fromHexString('FFF8D7DA');

    // Row 0: title.
    sheet.cell(at(0, 0)).value = TextCellValue('Pharmacy Roster — $monthLabel');
    sheet.cell(at(0, 0)).cellStyle = CellStyle(bold: true, fontSize: 14);

    // Two header rows: weekday letter (row 1) above the day number (row 2).
    sheet.cell(at(1, 2)).value = TextCellValue('Pharmacist');
    sheet.cell(at(0, 2)).value = TextCellValue('Que');
    for (final c in [0, 1]) {
      sheet.cell(at(c, 2)).cellStyle =
          CellStyle(bold: true, backgroundColorHex: headerFill);
    }

    for (var d = 1; d <= daysInMonth; d++) {
      final col = d + 1; // cols 0,1 are Que + Pharmacist.
      final date = DateTime(month.year, month.month, d);
      final isWeekend = date.weekday >= DateTime.saturday;
      final isHoliday = holidaysByDate.containsKey(Shift.keyFor(date));
      final fill = isHoliday
          ? holidayFill
          : isWeekend
              ? weekendFill
              : headerFill;
      sheet.cell(at(col, 1)).value =
          TextCellValue(DateFormat('E').format(date).substring(0, 1));
      sheet.cell(at(col, 1)).cellStyle = CellStyle(
        bold: true,
        backgroundColorHex: fill,
        horizontalAlign: HorizontalAlign.Center,
      );
      sheet.cell(at(col, 2)).value = IntCellValue(d);
      sheet.cell(at(col, 2)).cellStyle = CellStyle(
        bold: true,
        backgroundColorHex: fill,
        horizontalAlign: HorizontalAlign.Center,
      );
      sheet.setColumnWidth(col, 4.5);
    }
    sheet.setColumnWidth(0, 5);
    sheet.setColumnWidth(1, 26);

    for (var i = 0; i < people.length; i++) {
      final p = people[i];
      final row = i + 3;
      sheet.cell(at(0, row)).value = IntCellValue(p.queue);
      sheet.cell(at(0, row)).cellStyle =
          CellStyle(horizontalAlign: HorizontalAlign.Center);
      sheet.cell(at(1, row)).value = TextCellValue(p.displayName);
      for (var d = 1; d <= daysInMonth; d++) {
        final col = d + 1;
        final date = DateTime(month.year, month.month, d);
        final shifts = byCell['${p.id}|${Shift.keyFor(date)}'] ?? const [];
        if (shifts.isEmpty) {
          // Still shade weekend/holiday columns so the grid reads cleanly.
          final isWeekend = date.weekday >= DateTime.saturday;
          final isHoliday = holidaysByDate.containsKey(Shift.keyFor(date));
          if (isWeekend || isHoliday) {
            sheet.cell(at(col, row)).cellStyle = CellStyle(
              backgroundColorHex: isHoliday ? holidayFill : weekendFill,
            );
          }
          continue;
        }
        final codes = shifts
            .map((s) => (typesById[s.typeId] ?? ShiftType.unknown(s.typeId)).label)
            .join('/');
        final first = typesById[shifts.first.typeId];
        sheet.cell(at(col, row)).value = TextCellValue(codes);
        sheet.cell(at(col, row)).cellStyle = CellStyle(
          bold: true,
          horizontalAlign: HorizontalAlign.Center,
          backgroundColorHex:
              first == null ? ExcelColor.none : _tint(first.color),
        );
      }
    }
  }

  static void _buildSummarySheet(
    Sheet sheet, {
    required DateTime month,
    required String monthLabel,
    required List<Pharmacist> people,
    required List<ShiftType> orderedTypes,
    required Map<String, List<Shift>> byCell,
  }) {
    // Only this month's cells count toward the summary. byCell keys are
    // `pharmacistId|yyyy-MM-dd`; a `pharmacistId|yyyy-MM` prefix isolates the
    // month (the '|' guards against one id being a prefix of another).
    final monthPrefix = DateFormat('yyyy-MM').format(month);
    CellIndex at(int col, int row) =>
        CellIndex.indexByColumnRow(columnIndex: col, rowIndex: row);
    final headerFill = ExcelColor.fromHexString('FFE8EAF0');
    final totalFill = ExcelColor.fromHexString('FFF1F3F5');

    sheet.cell(at(0, 0)).value = TextCellValue('Shift Summary — $monthLabel');
    sheet.cell(at(0, 0)).cellStyle = CellStyle(bold: true, fontSize: 14);

    // Header: Que | Pharmacist | <type labels…> | Total shifts | Total hours
    final headers = <String>[
      'Que',
      'Pharmacist',
      for (final t in orderedTypes) t.label,
      'Total shifts',
      'Total hours',
    ];
    for (var c = 0; c < headers.length; c++) {
      sheet.cell(at(c, 1)).value = TextCellValue(headers[c]);
      sheet.cell(at(c, 1)).cellStyle = CellStyle(
        bold: true,
        backgroundColorHex: headerFill,
        horizontalAlign: c <= 1 ? HorizontalAlign.Left : HorizontalAlign.Center,
      );
    }
    sheet.setColumnWidth(0, 5);
    sheet.setColumnWidth(1, 26);
    for (var c = 0; c < orderedTypes.length; c++) {
      sheet.setColumnWidth(c + 2, 6);
    }
    sheet.setColumnWidth(orderedTypes.length + 2, 12);
    sheet.setColumnWidth(orderedTypes.length + 3, 12);

    final columnTotals = List<int>.filled(orderedTypes.length, 0);
    var grandShifts = 0;
    var grandHours = 0.0;

    for (var i = 0; i < people.length; i++) {
      final p = people[i];
      final row = i + 2;
      // Every shift this pharmacist holds in this month.
      final shifts = <Shift>[
        for (final entry in byCell.entries)
          if (entry.key.startsWith('${p.id}|$monthPrefix')) ...entry.value,
      ];
      final counts = List<int>.filled(orderedTypes.length, 0);
      var hours = 0.0;
      for (final s in shifts) {
        final idx = orderedTypes.indexWhere((t) => t.id == s.typeId);
        if (idx >= 0) counts[idx]++;
        hours += shiftHours(s.start, s.end);
      }

      sheet.cell(at(0, row)).value = IntCellValue(p.queue);
      sheet.cell(at(0, row)).cellStyle =
          CellStyle(horizontalAlign: HorizontalAlign.Center);
      sheet.cell(at(1, row)).value = TextCellValue(p.displayName);
      for (var c = 0; c < orderedTypes.length; c++) {
        sheet.cell(at(c + 2, row)).value = IntCellValue(counts[c]);
        sheet.cell(at(c + 2, row)).cellStyle =
            CellStyle(horizontalAlign: HorizontalAlign.Center);
        columnTotals[c] += counts[c];
      }
      final totalShifts = counts.fold<int>(0, (a, b) => a + b);
      sheet.cell(at(orderedTypes.length + 2, row)).value =
          IntCellValue(totalShifts);
      sheet.cell(at(orderedTypes.length + 2, row)).cellStyle =
          CellStyle(horizontalAlign: HorizontalAlign.Center, bold: true);
      sheet.cell(at(orderedTypes.length + 3, row)).value =
          DoubleCellValue(double.parse(hours.toStringAsFixed(1)));
      sheet.cell(at(orderedTypes.length + 3, row)).cellStyle =
          CellStyle(horizontalAlign: HorizontalAlign.Center);
      grandShifts += totalShifts;
      grandHours += hours;
    }

    // Totals row.
    final totalRow = people.length + 2;
    sheet.cell(at(1, totalRow)).value = TextCellValue('Total');
    sheet.cell(at(1, totalRow)).cellStyle =
        CellStyle(bold: true, backgroundColorHex: totalFill);
    sheet.cell(at(0, totalRow)).cellStyle =
        CellStyle(backgroundColorHex: totalFill);
    for (var c = 0; c < orderedTypes.length; c++) {
      sheet.cell(at(c + 2, totalRow)).value = IntCellValue(columnTotals[c]);
      sheet.cell(at(c + 2, totalRow)).cellStyle = CellStyle(
        bold: true,
        backgroundColorHex: totalFill,
        horizontalAlign: HorizontalAlign.Center,
      );
    }
    sheet.cell(at(orderedTypes.length + 2, totalRow)).value =
        IntCellValue(grandShifts);
    sheet.cell(at(orderedTypes.length + 2, totalRow)).cellStyle = CellStyle(
      bold: true,
      backgroundColorHex: totalFill,
      horizontalAlign: HorizontalAlign.Center,
    );
    sheet.cell(at(orderedTypes.length + 3, totalRow)).value =
        DoubleCellValue(double.parse(grandHours.toStringAsFixed(1)));
    sheet.cell(at(orderedTypes.length + 3, totalRow)).cellStyle = CellStyle(
      bold: true,
      backgroundColorHex: totalFill,
      horizontalAlign: HorizontalAlign.Center,
    );
  }

  /// Builds the report for [months] months starting at [startMonth] and saves
  /// it (browser download on web, native save elsewhere). When [useOriginal]
  /// is set the file name is suffixed `_original` to distinguish the baseline
  /// export. Returns the saved file name.
  static Future<String> download({
    required DateTime startMonth,
    required int months,
    required List<Pharmacist> pharmacists,
    required List<ShiftType> types,
    required Map<String, List<Shift>> shiftsByDay,
    Map<String, String> holidaysByDate = const {},
    bool useOriginal = false,
  }) async {
    final monthList = [
      for (var i = 0; i < months; i++)
        DateTime(startMonth.year, startMonth.month + i),
    ];
    final bytes = buildWorkbook(
      months: monthList,
      pharmacists: pharmacists,
      types: types,
      shiftsByDay: shiftsByDay,
      holidaysByDate: holidaysByDate,
    );
    final fmt = DateFormat('yyyy-MM');
    final range = monthList.length <= 1
        ? fmt.format(monthList.first)
        : '${fmt.format(monthList.first)}_to_${fmt.format(monthList.last)}';
    final name = 'roster_$range${useOriginal ? '_original' : ''}';
    await FileSaver.instance.saveFile(
      name: name,
      bytes: bytes,
      fileExtension: 'xlsx',
      mimeType: MimeType.microsoftExcel,
    );
    return '$name.xlsx';
  }
}

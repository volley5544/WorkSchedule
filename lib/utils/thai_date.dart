/// Thai-localized date formatting with Buddhist-era years (พ.ศ. = ค.ศ. + 543).
///
/// Kept dependency-free (no `intl` locale data / `initializeDateFormatting`
/// needed) by mapping the Thai month and weekday names directly. Used where
/// the UI shows dates in Thai, e.g. the Holidays screen.
library;

const _thaiMonths = [
  'มกราคม',
  'กุมภาพันธ์',
  'มีนาคม',
  'เมษายน',
  'พฤษภาคม',
  'มิถุนายน',
  'กรกฎาคม',
  'สิงหาคม',
  'กันยายน',
  'ตุลาคม',
  'พฤศจิกายน',
  'ธันวาคม',
];

const _thaiMonthsShort = [
  'ม.ค.',
  'ก.พ.',
  'มี.ค.',
  'เม.ย.',
  'พ.ค.',
  'มิ.ย.',
  'ก.ค.',
  'ส.ค.',
  'ก.ย.',
  'ต.ค.',
  'พ.ย.',
  'ธ.ค.',
];

// Indexed by DateTime.weekday (1 = Mon … 7 = Sun).
const _thaiWeekdays = [
  'จันทร์',
  'อังคาร',
  'พุธ',
  'พฤหัสบดี',
  'ศุกร์',
  'เสาร์',
  'อาทิตย์',
];

/// Buddhist-era year for [year] (Gregorian + 543).
int buddhistYear(int year) => year + 543;

/// e.g. `อังคาร 12 พฤษภาคม 2569`.
String thaiFullDate(DateTime d) =>
    '${_thaiWeekdays[d.weekday - 1]} ${d.day} ${_thaiMonths[d.month - 1]} ${buddhistYear(d.year)}';

/// e.g. `12 พ.ค. 2569`.
String thaiShortDate(DateTime d) =>
    '${d.day} ${_thaiMonthsShort[d.month - 1]} ${buddhistYear(d.year)}';

/// e.g. `พฤษภาคม 2569`.
String thaiMonthYear(DateTime d) =>
    '${_thaiMonths[d.month - 1]} ${buddhistYear(d.year)}';

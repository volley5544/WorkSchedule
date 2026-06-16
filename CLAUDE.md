# CLAUDE.md — Pharmacy Work Schedule

Flutter app (web-first, also Android/iOS/desktop) for hospital pharmacist
shift rosters. Firebase Auth (Google) + Cloud Firestore + Firebase Hosting.

## Firebase / deployment facts

- Firebase project id: **pharmacist-schedule**. Firebase CLI is installed and
  logged in on this machine; deploys have been run from this folder.
- Live URL: **https://pharmacist-schedule.web.app**
- Deploy flow after every feature (the user expects this):
  ```sh
  flutter analyze --no-pub
  flutter test
  flutter build web --release --pwa-strategy=none
  firebase deploy --only hosting --project pharmacist-schedule
  ```
- **Always build with `--pwa-strategy=none`** — the Flutter service worker
  made new deploys invisible on first load ("works in dev, not in prod").
  Hosting headers in `firebase.json` handle caching instead. NOTE: Flutter does
  **not** content-hash `main.dart.js` / `flutter_bootstrap.js` / `flutter.js`
  (stable filenames), so those + index.html are served **no-cache** (the headers
  list those explicitly, after the immutable `*.js` rule, so the later rule
  wins). Only genuinely-hashed chunks/assets stay `immutable`. Caching
  `main.dart.js` immutable served stale builds after deploys (an "uncaught error
  persists after the fix" bug) — don't revert that.
- Rules changes: edit `firestore.rules`, then
  `firebase deploy --only firestore:rules --project pharmacist-schedule`.
  Rules deployed = required; undeployed rules caused the original
  "eternal loading after login" bug (permission-denied swallowed).

## Firestore data model

| Collection | Doc shape | Read | Write |
|---|---|---|---|
| `users/{uid}` | email, displayName, role (`viewer`/`editor`/`admin`), photoUrl | signed-in | self-create as viewer; admin updates roles |
| `shifts/{id}` | dateKey (`yyyy-MM-dd`), type (= shiftType doc id, field name is `type`), start/end (`HH:mm`), pharmacist (denormalized full name), pharmacistId, note, createdBy | public | editor/admin |
| `shiftTypes/{id}` | label (ช/ย/บ/ด), description, start, end, color (int ARGB), days (list of weekday ints 1=Mon..7=Sun), sortOrder | public | admin |
| `pharmacists/{id}` | name, title (คำนำหน้า), lastname, nickname, queue (เลขที่ Que, orders roster rows), uid (optional link to a user account → powers "My shifts") | public | admin |
| `config/nameTitles` | values: [string] (title dropdown choices; defaults นาย/นางสาว/นาง/คุณ when doc missing) | public | admin |

Public reads exist so guests can view without login (user-approved tradeoff).
`users` stays signed-in-only.

Denormalization convention: shifts store both `pharmacistId` (resolve live)
and `pharmacist` (name snapshot, survives pharmacist deletion). Deleted shift
types / pharmacists render as grey "unknown" fallbacks (`ShiftType.unknown`,
fallback entries in the editor dropdowns) — never crash, never block editing.

## App structure (lib/)

- `main.dart` — auth gate: waiting → login → (guest home | profile-wait →
  home). Shows `_ProfileErrorScreen` on profile stream errors instead of
  spinning forever. Guest mode = `AppUser.guest` (uid '', `isGuest`).
- `models/` — `app_user.dart` (roles + guest), `shift.dart`,
  `shift_type.dart` (incl. `everyDay`, `daysLabel`, seedable `defaults`
  where ช is Sat–Sun only), `pharmacist.dart` (`fullName` joins
  title+name+lastname Thai-style: no space after title; `displayName` adds
  nickname in parens).
- `services/auth_service.dart` — Google sign-in (popup on web), creates
  `users` doc on first sign-in.
- `services/schedule_service.dart` — all Firestore CRUD + `autoSchedule()`
  (see below) + `seedDefaultShiftTypes()` + `nameTitles()` stream.
- `screens/home_screen.dart` — three views via SegmentedButton:
  **My shifts** (filter by pharmacists linked to current uid; calendar in
  `codeOnly` mode = big shift-code chips, no names), **By day** (calendar +
  day panel), **Roster** (matrix). App bar: ✨ auto-schedule (editors+),
  role chip, avatar menu (admin entries: Manage users / Shift types /
  Pharmacists). Guests: only By day + Roster, Sign in button instead.
- `screens/shift_types_screen.dart` — admin CRUD; dialog has label,
  description, time pickers, active-day FilterChips, 12-color palette;
  empty state seeds ช/ย/บ/ด defaults.
- `screens/pharmacists_screen.dart` — admin CRUD; dialog has title dropdown
  (configurable via badge icon in app bar → `_TitlesDialog` →
  `config/nameTitles`), name/lastname/nickname, queue number, linked-account
  dropdown (from `users`).
- `screens/manage_users_screen.dart` — role SegmentedButtons; admins can't
  demote themselves.
- `widgets/month_calendar.dart` — custom month grid; `compact` (dots) and
  `codeOnly` modes. Wide ≥840px shows chips inline.
- `widgets/roster_table.dart` — pinned name column + horizontally scrollable
  day grid (Scrollbar always visible, mouse-drag enabled via
  ScrollConfiguration). Tap name = highlight whole row (toggle). Cell tap
  (editors): empty→add prefilled, one→edit, many→chooser dialog. 15px bold
  code chips, weekend shading, today highlight.
- `widgets/shift_editor_dialog.dart` — type + pharmacist dropdowns (config
  driven), date/time pickers, note. Selecting a type auto-fills its hours.
- `widgets/auto_schedule_dialog.dart` — start month arrows, months 1–6,
  "Regenerate existing months" switch; returns a record
  `({DateTime startMonth, int months, bool replaceExisting})`.

## Auto-scheduler semantics (ScheduleService.autoSchedule)

- Walks each day of the range; for each shift type active on that weekday
  (by `days`), in sortOrder, assigns the next pharmacist in queue order,
  round-robin 1→2→…→n→1. One pharmacist per shift.
- Rotation **continues from the month before startMonth**: last shift there
  (sorted by dateKey, then type sortOrder, then start) → next pharmacist.
- `replaceExisting=false`: existing (day×type) slots are kept and skipped
  (rotation not advanced). `true`: whole range deleted then regenerated.
- Batched writes, flushed at 450 ops (Firestore 500 cap).
- ช must have days=[6,7] — Mon–Fri 08:30–16:30 is normal work for everyone,
  so weekdays only get ย/บ/ด. Docs created before the `days` field existed
  default to every day; user was told to edit ช in prod config (verify).

## Testing / quality

- `flutter analyze --no-pub` and `flutter test` after every change — keep
  both green (this has been the working rhythm).
- Tests: `test/month_calendar_test.dart` only (widget tests + keyFor).
  `autoSchedule` has no tests (would need fake_cloud_firestore).

## Known quirks / history

- Google avatar 429s (lh3.googleusercontent.com rate limit): handled with
  `onForegroundImageError` fallbacks; console line is browser-level noise.
- Legacy shifts created before pharmacistId/type-id migrations show as
  unknown/grey in Roster & My shifts until re-saved; By day still shows them.
- `setState`-after-dispose in login is guarded with `mounted` checks.
- Thai context: month names like "july 69" = Buddhist Era (2569 = 2026 CE).
  UI text is English; data (names, shift codes ช ย บ ด) is Thai.
- User communicates in brief English; prefers features shipped + deployed +
  noted in README each time. README has sections per feature — keep updating
  it (the user explicitly asks for this).

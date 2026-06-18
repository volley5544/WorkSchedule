# Pharmacy Work Schedule

A responsive, cross-platform (web / Android / iOS / desktop) Flutter app for
creating, managing, and viewing hospital pharmacists' work schedules in a
calendar format. Sign-in is via Google, with three access levels:

| Role | Can do |
|--------|--------|
| Guest  | View the By day & Roster tabs without signing in |
| Viewer | View the schedule incl. My shifts (default for every new sign-in) |
| Editor | Viewer + create / edit / delete shifts |
| Admin  | Editor + manage user roles and shift types |

Visitors without an account tap **Continue without signing in** on the login
page: they get a view-only home with just the By day and Roster tabs and a
Sign in button in the app bar. To support this, the schedule collections
(`shifts`, `shiftTypes`, `pharmacists`, `config`) are publicly readable;
writes still require the editor/admin role and the `users` collection stays
restricted to signed-in users.

## Calendar views

The schedule page has four views, switchable with the segmented control
under the month bar:

| View | Shows |
|------|-------|
| **My shifts** | Only the signed-in user's own shifts (requires the admin to link the user's account to a pharmacist — see below) |
| **By day** | The month calendar plus a day-detail panel listing everyone working that day (a day can hold several pharmacists, each on a different shift) |
| **Roster** | A modern roster matrix like the classic printed table: one row per pharmacist, one column per day, colored shift codes in the cells. The name column stays pinned while the days scroll horizontally; weekends are shaded and today is highlighted. Editors can tap any cell to add or edit that pharmacist's shift on that day. |
| **Original** | The **read-only** roster matrix as it was auto-generated, before any shift swaps (see [Auto scheduling](#auto-scheduling)). Same layout as Roster but cells can't be edited — keep it open beside Roster to see exactly which shifts pharmacists have exchanged. |

## Pharmacist configuration

The work group's pharmacist list lives in the `pharmacists` collection and
is managed by admins via **avatar menu → Pharmacists**:

- **Add / edit / remove** pharmacists. Each has a name, optional title
  (คำนำหน้า), last name, and nickname, and a queue number (เลขที่ Que) that
  orders the roster rows.
- **Two independent orders**, both drag-reorderable via the toggle at the top of
  the Pharmacists screen (grab the ⠿ handle):
  - **Display order** (`showOrder`) — sorts pharmacists **everywhere they're
    listed in the UI** (Pharmacists screen, Roster/Original tables, the shift
    editor & custom-rotation pickers), e.g. by seniority ("oldest first").
  - **Schedule queue** (`queue`, เลขที่ Que) — the **auto-schedule rotation
    order only**; the UI never sorts by it.
  - Both are also editable as number fields in the pharmacist dialog. A
    `showOrder` of `0` is "unset" — those pharmacists fall back to queue order,
    so existing data shows queue order until you set one.
- **Part-time** (toggle in the pharmacist dialog): a part-time pharmacist is
  **left out of the default auto-schedule rotation**, so they never get the
  regular shifts automatically. They're only assigned where you add them to a
  shift type's **custom rotation**. Typical setup: mark the part-timers, create
  a shift type for them with a custom rotation listing those people, and drag
  that type to the top of the Shift types list so it's filled first.
  - **Part-timers take priority within a custom rotation** (see the priority
    tiers below): a part-timer with a Day/week rule is a *constrained* entry, so
    they win their eligible days. Constrain the part-timer(s) to the **1st–4th**
    occurrences (Day/week rules → weeks 1,2,3,4) and they cover weeks 1–4 (two or
    more rotate among themselves) while the open rotation only fills a 5th
    Saturday.
- **Rotation priority tiers** — each day, for each shift type, the auto-scheduler
  fills the slot from the first non-empty tier, in this order:
  1. **Weekday pin** (a specific person fixed to that weekday).
  2. **Constrained entries** — any custom-rotation pharmacist with a **Day/week
     rule** (specific weekdays, weeks-of-month, or Week A/B). The admin asked for
     that person on those exact days, so when one is eligible they **win over the
     open rotation** — e.g. a pharmacist set to the **5th Saturday only** gets the
     5th Saturday even though the unconstrained rotation would otherwise take it.
     Multiple eligible constrained entries rotate among themselves.
  3. **Unconstrained part-timers.**
  4. **Unconstrained normals** — the open rotation that fills everything else.

  Each tier keeps its own per-bucket counter and continues across months.
- **Name titles are configurable**: the title dropdown's choices (default
  นาย / นางสาว / นาง / คุณ) are edited via the badge icon in the
  Pharmacists screen's app bar and stored in `config/nameTitles`.
- **Link to an account** (optional): connects a pharmacist row to a signed-in
  Google account so that user's "My shifts" view works.
- The shift editor picks the pharmacist from this list (no more free-text
  names). Shifts also store the name at save time, so removing a pharmacist
  later doesn't blank out historical entries.

## Auto scheduling

Editors and admins can fill the roster automatically via the ✨ button in the
app bar:

- Pick a **start month** and **how many months** to fill (1–6); e.g. starting
  July and running 3 months fills July, August, and September in one go.
- **Independent rotation per shift type**: each shift type keeps its *own* turn
  order — assigning ย doesn't move บ's or ด's pointer. One pharmacist per
  (day × shift type).
- **Separate weekday / weekend / holiday counters**: within a type, weekdays
  (Mon–Fri), weekends (Sat–Sun), and holidays each rotate independently, so
  weekday duty and the (less frequent) weekend duty are each shared out fairly
  on their own cycle.
- **Holidays are non-working days**: on a holiday only shift types marked *Runs
  on holidays* are scheduled (a holiday's weekday is ignored), so e.g. ช covers
  a holiday that lands on a Tuesday.
- **Pin pharmacist by weekday** (optional, per type): fix a specific pharmacist
  for a shift on a given weekday — on normal days, weekends, and holidays alike
  (e.g. Tue/Wed/Thu → A, Fri/Sat → B), with the other weekdays falling through
  to the rotation. A pinned pick doesn't consume a rotation turn.
- **No scheduling guards — the roster flags problems instead**: the
  auto-scheduler has **no** per-day shift cap, **no** continuous-hours cap, and
  **no** overlap check; it simply fills every slot by rotation, matching how the
  hospital actually rosters (back-to-back ช + บ + ด, a full 24h, is allowed).
  Instead, the **Roster** and **Original** tables **highlight** any pharmacist's
  day in red — with a tooltip explaining why — when that day has:
  - **more than 2 duty blocks**, where the implicit Mon–Fri 08:30–16:30 work
    counts as one (so a weekday fits only *one* scheduled shift on top of it; a
    weekend/holiday fits two), or
  - **more than 18h continuous** on duty (also counting the Mon–Fri 08:30–16:30
    work and chaining a night shift into the next day), or
  - **overlapping shift times**.

  A human reviews the flagged cells and fixes them by editing/swapping shifts.
  (Detection lives in the pure, unit-tested `services/shift_conflicts.dart`.)
- **Linked shifts (same pharmacist)**: a shift type can be set to follow
  another — on days the leader runs, the linked type is given the *same*
  pharmacist instead of rotating. This is how weekends/holidays put one person
  on both ช and บ: บ is linked to ช, so whoever draws ช also gets บ. On
  weekdays (where ช doesn't run) บ just rotates as the normal evening shift.
  Exchanging is then trivial — an editor edits either the ช or the บ shift's
  pharmacist independently.
- **Custom rotations**: a type can use its own ordered list of pharmacists
  instead of the global queue (e.g. ด's reshuffled order), and each participant
  can be limited to certain weekdays and/or *every other week* (Week A / Week B)
  — covering shifts like ณ where someone only works, say, Thursdays on alternate
  weeks. Configure this under **Shift types** (see below).
- **Continuity**: every counter picks up where the previous month left off — if
  June's last weekday บ went to pharmacist 5, July's first weekday บ starts with
  pharmacist 6. Continuation reads the previous month's **Original** baseline
  (not the live Roster), so one-off shift **swaps don't drift the rotation** —
  it always continues from the clean auto-generated order. (If that month was
  never auto-generated, the rotation just starts fresh.)
- **Regenerate existing months** (toggle in the dialog): off by default —
  existing shifts are kept and only empty (day × shift type) slots are
  filled. Turn it on to delete everything in the selected months and
  reschedule them from scratch (still continuing the rotations from the
  month before the start month).

Every auto-schedule run also saves a **read-only snapshot** of the generated
roster to a separate `originalShifts` collection. The editable **Roster** tab
is what pharmacists then swap shifts on; the **Original** tab keeps showing the
untouched baseline so you can compare the two and see who exchanged what. The
snapshot is updated per (day × shift type) slot each time you generate —
regenerating a month resets that month's baseline, while a fill-empty run only
adds baseline entries for the newly filled slots.

Each shift type has configurable **active days**. By default ช runs only on
Sat–Sun (Mon–Fri 08:30–16:30 is the normal working day for the whole group),
while ย / บ / ด run every day — so weekdays get only ย, บ, ด on the
schedule. Admins change this with the day chips in the shift type dialog. Each
type also has a **Runs on holidays** switch and an optional **custom rotation**
(see [Shift type configuration](#shift-type-configuration)).

## Holidays

The special after-hours clinic's closed days
(วันหยุดคลินิกพิเศษเฉพาะทางนอกเวลาราชการ) live in the `holidays` collection.
**Every signed-in user** can open **avatar menu → Holidays** to view the list
(dates shown in Thai with Buddhist-era years, e.g. *อังคาร 12 พฤษภาคม 2569*);
only **admins** see the add / edit / remove / seed actions:

- **Add / edit / remove** a holiday — each is a date plus an optional
  name/reason. There's one entry per date (the date is the document id), so
  re-adding the same day just updates it.
- **First-time seeding**: on an empty list the screen offers one click to load
  the posted **B.E. 2569 (2026)** clinic holidays — May 2, 3, 4, 13, 30, 31;
  June 1, 3; July 28, 29, 30; Aug 12; Oct 12–16 (มติ ครม.); Oct 23, 24, 25;
  Dec 5, 6, 7, 10, 31. (B.E. 2569 = 2026 CE; dates are stored as Gregorian.)
- **Where they show**: holidays are shaded red on the month calendar (with a
  small red dot and a tooltip of the name) and on the Roster / Original day
  columns.
- **Auto-scheduling treats them as non-working days**: on a holiday only shift
  types with **Runs on holidays** turned on are generated (the date's weekday is
  ignored), and they rotate on their own holiday counter — see
  [Auto scheduling](#auto-scheduling).

Holidays are publicly readable (they appear on the guest calendar); only admins
can change them.

## Shift type configuration

Shift types (code, description, working hours, color) are **not hardcoded** — they live in
the `shiftTypes` Firestore collection and are managed in-app by admins via
**avatar menu → Shift types**, where each type can be added, edited, or
deleted. The shift editor's dropdown, the calendar chips/dots, and the
day-detail panel all resolve their labels and colors live from this config.

On a fresh database the config page offers one-click seeding of the hospital's
standard pharmacist shifts:

| Code | Description | Hours |
|------|-------------|-------------|
| ช | เวรเช้า | 08:30–16:30 |
| ย | เวรเย็น | 16:30–20:30 |
| บ | เวรบ่าย | 16:30–23:30 |
| ด | เวรดึก | 23:30–08:30 |

The list is **drag-to-reorder** (grab the ⠿ handle). The order sets each type's
`sortOrder`, which is the **priority the auto-scheduler assigns shifts in each
day** — the type at the top is assigned first. This also matters for
*Same pharmacist as* links (the leader must sit above its follower).

Each type's dialog also configures how the auto-scheduler treats it:

- **Active days** — the weekdays the type runs on (the day chips).
- **Runs on holidays** — when on, the type is scheduled on holiday dates (which
  the scheduler treats as non-working days, ignoring the weekday list).
- **Pin pharmacist by weekday** — for each weekday you can fix a specific
  pharmacist (or leave it as *Use rotation*) for this shift. Applies on normal
  days, weekends, and holidays alike — e.g. Tue/Wed/Thu → A, Fri/Sat → B, the
  rest rotate.
- **Same pharmacist as** — optionally link this type to another: on days the
  chosen leader runs, this type copies its pharmacist instead of rotating (e.g.
  set บ to follow ช so weekends/holidays put one person on both). On other days
  it rotates normally. To exchange, edit either shift's pharmacist on its own.
- **Custom rotation** — off by default (rotate through the global pharmacist
  queue). Turn it on to give the type its own ordered participant list:
  drag the handle to reorder, add/remove pharmacists, and per pharmacist
  set **day / week rules** (the ⚙ icon) — restrict them to certain weekdays,
  to certain **occurrences of that weekday in the month** (1st–5th — e.g. "only
  the 5th Saturday", or "1st–4th Saturdays" to skip a 5th one), and/or to
  alternating weeks (**Week A** / **Week B**). This powers ด's reshuffled order,
  ณ-style "only Thursdays, every other week" rosters, and opt-in/opt-out of the
  occasional 5th-weekday shift.
  *(Week A/B alternate every calendar week from a fixed reference Monday, so the
  pattern stays stable across months and years.)*

Each shift on the roster stores the id of its shift type, so renaming or
recoloring a type updates the whole calendar instantly. Deleting a type keeps
existing roster entries intact — they render in grey as an unknown type until
edited. Security rules allow every signed-in user to read the config but only
admins to change it.

## One-time Firebase setup

The app uses Firebase Authentication (Google provider) and Cloud Firestore.

1. Create a project at <https://console.firebase.google.com>.
2. **Authentication → Sign-in method → enable Google.**
3. **Firestore Database → Create database** (production mode).
4. Connect this app to the project:

   ```sh
   dart pub global activate flutterfire_cli
   flutterfire configure        # overwrites lib/firebase_options.dart
   ```

5. Deploy the security rules (they enforce the roles server-side):

   ```sh
   npm install -g firebase-tools
   firebase login
   firebase deploy --only firestore:rules
   ```

   Or paste the contents of `firestore.rules` into
   Firestore → Rules in the console.

6. **Bootstrap the first admin:** sign in to the app once, then in the
   console open Firestore → `users` → your document and change
   `role` from `viewer` to `admin`. From then on you can promote others
   from inside the app (avatar menu → *Manage users*).

> For Google sign-in on web, add your hosting domain (and `localhost`) under
> Authentication → Settings → Authorized domains.

## Run

```sh
flutter run -d chrome        # web
flutter run                  # connected mobile device / emulator
```

## Troubleshooting

**Endless loading spinner after Google sign-in** — sign-in succeeded but the
app could not read/create your profile in Firestore, almost always because the
security rules were never deployed (a new database in production mode denies
everything, so `users/{uid}` is unreadable). Fix: deploy the rules (setup
step 5):

```sh
firebase deploy --only firestore:rules
```

The auth gate now shows an error screen with the underlying Firestore message
(instead of spinning forever) when the profile stream fails, and the login
screen guards its `setState` calls with `mounted` so the
`setState() called after dispose()` console error no longer appears.

## Deploy the web app

Hosting is already configured in `firebase.json` (public dir `build/web`,
SPA rewrite to `index.html`, immutable caching for hashed assets, `no-cache`
for `index.html` / service worker so new releases roll out immediately).
To ship a new version:

```sh
flutter build web --release --pwa-strategy=none
firebase deploy --only hosting
```

`--pwa-strategy=none` disables the Flutter service-worker cache. Without it,
browsers keep serving the previous build on the first load after a deploy
(the service worker only swaps versions on a later reload), which makes new
features look "missing" in production. The hosting cache headers already
provide fast repeat loads, so the service worker isn't needed.

Live at <https://pharmacist-schedule.web.app>.

### Automatic deploys (CI/CD)

`.github/workflows/firebase-hosting-deploy.yml` runs on every push to `main`
(and on demand from the Actions tab). It pins Flutter to the project version,
runs `flutter analyze` + `flutter test` as gates, builds the web app with
`--pwa-strategy=none`, and deploys to the live Hosting channel — so a push is
all it takes to ship.

One-time setup — add a Firebase service-account key as a repo secret named
**`FIREBASE_SERVICE_ACCOUNT`**:

1. Firebase Console → ⚙ **Project settings → Service accounts →
   Generate new private key** → download the JSON.
2. GitHub repo → **Settings → Secrets and variables → Actions →
   New repository secret**, name `FIREBASE_SERVICE_ACCOUNT`, paste the whole
   JSON file contents as the value.

   Or with the GitHub CLI:

   ```sh
   gh secret set FIREBASE_SERVICE_ACCOUNT < path/to/service-account.json
   ```

Until that secret exists the build/test steps still run, but the deploy step
fails. Firestore **rules** are not deployed by CI (only Hosting) — keep using
`firebase deploy --only firestore:rules` for rule changes.

## Project structure

```
lib/
  main.dart                     app bootstrap + auth gate
  firebase_options.dart         generated by flutterfire configure
  models/  app_user.dart        user profile + role enum
           shift.dart           shift model (references type & pharmacist by id)
           shift_type.dart      configurable shift type + hospital defaults
           pharmacist.dart      roster member (name, queue no., linked account)
           holiday.dart         clinic closed day (+ B.E. 2569 seed list)
  services/ auth_service.dart   Google sign-in, profile creation
            schedule_service.dart  Firestore queries for shifts, config & users
            schedule_planner.dart  pure auto-schedule rotation engine (testable)
  screens/  login_screen.dart
            home_screen.dart    responsive layout + My/Day/Roster/Original switch
            manage_users_screen.dart   admin role management
            shift_types_screen.dart    admin shift type add/edit/delete
            pharmacists_screen.dart    admin pharmacist add/edit/remove + linking
            holidays_screen.dart       admin clinic-holiday add/edit/remove + seed
  widgets/  month_calendar.dart custom responsive month-grid calendar
            day_shifts_panel.dart
            roster_table.dart   pharmacist × day roster matrix
            shift_editor_dialog.dart
  utils/   thai_date.dart       Thai date formatting + Buddhist-era years
firestore.rules                 role-based security rules
.github/workflows/firebase-hosting-deploy.yml   CI/CD: auto-deploy on push
```

The calendar is a custom component (no third-party calendar package): on wide
screens each day cell shows shift chips inline; below 840 px it switches to a
compact grid with colored dots plus a day-detail list, so it works well on
phones.

## Changelog

### 2026-06-17

- **"One shared rotation, every day" shift-type option** — a new toggle in the
  shift-type editor makes a type run **every day** (weekday, weekend, holiday
  alike — its active-days list and "Runs on holidays" are ignored) and rotate
  through a **single continuous counter** instead of separate
  weekday/weekend/holiday rotations. Built for **ด (night duty)**: add one ด with
  a custom rotation and it cycles 1→2→…→n→1 across the whole month, unbroken by
  weekends or holidays. (`ShiftType.singleRotation`; `schedule_planner.dart` adds
  a `DayBucket.all`; 2 new tests.)
- **Constrained roster entries now win over the open rotation** — a custom-
  rotation pharmacist with a **Day/week rule** (e.g. "5th Saturday only") was
  only made *eligible* on those days, not *preferred*, so an unconstrained
  pharmacist whose turn it was could grab the slot first (a pharmacist set to the
  5th Saturday of Aug 2026 / the 29th didn't get it). The scheduler now resolves
  each day through **priority tiers** — weekday pin → constrained entries →
  unconstrained part-timers → unconstrained normals — so a constrained pharmacist
  takes their eligible day. This also unifies the earlier part-time fix (a
  part-timer limited to weeks 1–4 is just a constrained entry). (`schedule_planner.dart`;
  new test.)
- **Dropped the last scheduling guard (overlap) — the roster now flags problems
  instead** — the auto-scheduler no longer skips a pharmacist for *any* reason
  (no overlap check either); it fills every slot purely by rotation. To keep
  conflicts visible, the **Roster** and **Original** tables now **highlight a
  pharmacist's day in red** (with a tooltip) when it has **more than 2 shifts**,
  **more than 18h continuous** on duty, or **overlapping shift times**. The
  detection is a new pure module, `services/shift_conflicts.dart` (11 tests).
  The ">2 duties" check counts the implicit **Mon–Fri 08:30–16:30 normal work**
  as one block, so a weekday with two scheduled shifts on top of it is flagged
  (e.g. Fri 31 Jul 2026: normal work + ณ + ด).
- **Removed the per-day shift cap and the 18h continuous-duty cap** — the
  hospital genuinely allows back-to-back duty, so the auto-scheduler no longer
  limits how many shifts a pharmacist takes in a day or how many continuous
  hours they're on duty. A person can now be rostered ช + บ + ด on the same day
  (a full 24h). The only per-pharmacist guard left is **overlap** — they still
  won't be booked into two shifts at the *same clock time* (e.g. ย 16:30–20:30
  and บ 16:30–23:30). This also applies to weekday pins and linked types: each
  is honoured unless it would overlap, in which case it falls through to the
  rotation. (`schedule_planner.dart`; the implicit-normal-work / span machinery
  was deleted.) **Re-run auto-schedule with "Regenerate existing months" on for
  any month you want re-balanced under the new rules.**
- **Part-timers are now the priority pool in a custom rotation** — when a shift
  type's custom rotation mixes part-time and normal pharmacists, the
  auto-scheduler fills each day from the **part-timers first** and only falls
  through to a normal pharmacist on days no part-timer is eligible. So with the
  part-timer(s) constrained to the **1st–4th** occurrences of a weekday (Day /
  week rules → month weeks 1,2,3,4), they cover weeks 1–4 (multiple part-timers
  rotate among themselves) and a **normal pharmacist only picks up a 5th
  occurrence** (e.g. a 5th Saturday). Each pool keeps its own rotation counter,
  continuing across months. Fixes the previous behavior where part-time and
  normal interleaved as one round-robin, so a normal pharmacist wrongly grabbed
  weeks 2 and 4. (`schedule_planner.dart`; 2 new planner tests, 19 total.)

### 2026-06-16

- **Languages & appearance** — the UI can switch between **Thai (default)** and
  **English**, and between **Follow device / Light / Dark** themes, from a new
  **Settings** dialog (avatar menu → Settings, or the gear on the login screen).
  The choice is saved locally (`shared_preferences`) and applied app-wide.
  Strings live in `lib/l10n/app_text.dart`; preferences in
  `lib/services/app_settings.dart`. The everyday UI (login, home/navigation,
  calendar, roster, day panel, shift editor, auto-schedule) is translated; the
  **admin config dialogs** (Shift types, Pharmacists, Holidays, Manage users)
  are still English and tracked for a follow-up.

### 2026-06-15

- **Auto-scheduler rebuilt** — the rotation now matches the real hospital
  method: each shift type rotates **independently**, with **separate
  weekday / weekend / holiday counters**, each continuing from the previous
  month. Holidays are scheduled as non-working days (only types with the new
  **Runs on holidays** flag), the scheduler never double-books a pharmacist on
  two time-overlapping shifts, and a type can use a **custom rotation** —
  its own ordered pharmacist list with per-person weekday + *every-other-week*
  (Week A/B) rules (covers ด's reshuffle and ณ-style "Thursdays alternate
  weeks"). It also supports **pinning a pharmacist by weekday** — fix a specific
  person for a shift on a given weekday, on normal days/weekends/holidays alike
  (e.g. Tue/Wed/Thu → A, Fri/Sat → B), the rest rotate. A pharmacist's
  **continuous** on-duty time is also capped at **18 hours** — counting the
  implicit Mon–Fri 08:30–16:30 normal work and chaining shifts that touch across
  midnight (so a night shift that runs into the next day's normal work counts,
  and blocks piling another shift on top), plus a **max 2 duty items per day**
  (the weekday normal work being one — so a weekday fits only one scheduled shift
  on top of it). Shift types can also be **linked**
  (*Same pharmacist as*) so one person covers both — e.g. บ follows ช on
  weekends/holidays, while บ still rotates on its own on weekdays; exchanging is
  just editing either shift. The scheduling logic was extracted into a pure,
  unit-tested `schedule_planner.dart` (17 tests).
- **Shift ordering** — every table (Roster, Original, the day panel and calendar
  cells) now lists a day's shifts strictly by **start time, earliest first**,
  parsed by actual minutes so unpadded/legacy times sort correctly.
- **Original schedule tab** — auto-schedule now saves a read-only snapshot of
  the generated roster to a separate `originalShifts` collection. A new
  **Original** tab shows that untouched baseline next to the editable
  **Roster**, so shift exchanges are visible by comparing the two.
- **Holidays** — new `holidays` collection, admin screen, and the posted
  B.E. 2569 clinic-closed days as a one-click seed; holidays are marked red on
  the calendar and roster. Visible to every signed-in user (read-only unless
  admin), with dates shown in Thai + Buddhist-era years.
- **Mobile UX** — "My shifts" shows shift codes (not just dots) on phones, and
  the By day / My shifts pages now scroll as a whole on small screens. The
  compact calendar now reserves a fixed height for the shift-code row, so days
  without a shift line up exactly with days that have one (the day numbers no
  longer jump up/down as you scan the month).
- **Fixes** — held Firestore streams as state fields to stop the empty-table
  flash when switching tabs; made the view switcher scroll so the Original tab
  can't be clipped.
- **CI/CD** — added a GitHub Actions workflow that builds and deploys to
  Firebase Hosting on every push to `main` (see
  [Automatic deploys](#automatic-deploys-cicd)).

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
- The generator walks day by day and assigns **one pharmacist per shift** in
  queue order (1 → 2 → 3 → … → back to 1), covering every shift type active
  on that weekday.
- **Continuity**: the rotation picks up where the previous month left off —
  if 30 June's last shift went to pharmacist 5, 1 July starts with
  pharmacist 6.
- **Regenerate existing months** (toggle in the dialog): off by default —
  existing shifts are kept and only empty (day × shift type) slots are
  filled. Turn it on to delete everything in the selected months and
  reschedule them from scratch (still continuing the rotation from the
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
schedule. Admins change this with the day chips in the shift type dialog.

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
  columns. They're informational for now — auto-scheduling does not yet skip
  them.

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
firestore.rules                 role-based security rules
```

The calendar is a custom component (no third-party calendar package): on wide
screens each day cell shows shift chips inline; below 840 px it switches to a
compact grid with colored dots plus a day-detail list, so it works well on
phones.

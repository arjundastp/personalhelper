# DayMate

**DayMate** (formerly Remindly) is an offline Android app for reminders and your work day (Flutter UI with a native Android alarm engine). Use it for medicines, drinking water, vehicle pollution and insurance renewals, bills, birthdays and anything else.

## Download

**[⬇ Download DayMate for Android](https://github.com/arjundastp/personalhelper/raw/main/downloads/DayMate.apk)** (version 1.12.1, about 20 MB, Android 8.0 or newer)

- Most phones: [`DayMate.apk`](https://github.com/arjundastp/personalhelper/raw/main/downloads/DayMate.apk)
- Older or very low-cost phones (32-bit): [`DayMate-older-phones.apk`](https://github.com/arjundastp/personalhelper/raw/main/downloads/DayMate-older-phones.apk)

**Updating from version 1.6 or older:** from 1.7 on, DayMate is signed with its own permanent key, so Android needs the old app removed once.
In the old app use **Settings → Backup → Back up to a file** (1.7+), or note your reminders, then uninstall it, install 1.7, and use **Restore from a file**.

To install: open the downloaded file on your phone. If Android asks, allow your browser or Files app to install apps.
On first start, tap **Allow** so reminders can ring and show full screen.

## Features
- **Reminders that repeat:** once, every N days, chosen weekdays (every N weeks), every N months (for example a pollution certificate every 6 months), yearly, or every few hours within a time window (for example water every 2 h from 8 AM to 10 PM). Each reminder can have an end date.
- **Quick-start templates:** Take medicine, Drink water, Pollution check (PUC), Vehicle insurance, Vehicle service, Pay a bill, Birthday, Doctor visit, Exercise, Water the plants.
- **Sound on/off per reminder:** turn the sound off for a silent reminder that only shows the full-screen alert (and vibrates if vibration is on).
- **Daily Sprint (optional, Settings → Extras → Add Daily Sprint):** a work-day planner on its own bottom tab.
  Add small tasks for the day in a message-style box. A morning nudge comes at 10:30 AM and a full-screen
  "How did today go?" alert at 6:30 PM (both editable, work days only). Mark each task Done, Partly done
  (with a note on what is left; the rest can continue on the next work day, labelled "Continued from …"), Not done
  (optionally moved to the next work day, labelled "Moved from …") or Paused (goes to the Parked tasks list).
  Any task can have a note; a partly done task counts as half in the completion %.
  Mark days as leave, half-day leave or public holiday (also in advance); reports show working days,
  leave taken, holidays and days reported for the period, the month and the year.
  **Goals:** long-term goals with a progress bar, target date and dated progress notes.
  **Achievements:** log wins by category and link them to goals; "Share for review" builds a ready-to-paste summary.
  Tabs across the top (Today · Goals · Achievements · Insights · Parked · History); Insights shows completion %, a daily progress chart,
  how tasks ended, an activity calendar, best weekdays and tasks that keep slipping. Code: `lib/sprint/`, `android/.../Sprint.kt`.
- **Team summary (optional, Settings → Extras → Add Team summary):** a third bottom tab with a short summary of
  yesterday's Microsoft Teams chats. DayMate keeps summaries 10 days on the phone. Three ways to get them:
  - **Summaries from my endpoint (Claude routine)** (default): a scheduled Claude routine reads Teams with Claude's
    Microsoft 365 connector (read-only), writes the summary and sends it to your own small Cloudflare Worker;
    DayMate only reads it with a separate read key. Summaries there expire after 2 days. In this mode chats are
    processed in the cloud, not on the phone. Setup and the routine prompt: [`tools/cloudflare-worker/`](tools/cloudflare-worker/).
  - **Microsoft Graph · Chat.Read:** sign in with your work account; needs your company's admin approval. Only
    read requests are made, and Chat.Read cannot write. Summarised on the phone (Gemini Nano via ML Kit GenAI when
    available, otherwise a simple digest).
  - **Company Teams MCP server (Agent 365):** only list/get/search tools can be called; everything else is
    blocked in code (`Team.kt`). Summarised on the phone, like Graph.
  For the sign-in options, your company's tenant and app IDs are typed into the app and stored only on the phone,
  so nothing company-specific is in this repository or the public APK. DayMate does not read notifications, so
  Google Play Protect does not block installing the APK.
- **Home (first screen once Daily Sprint or Team summary is on):** a warm greeting with your name and the date,
  **Needs your attention** (missed reminders, Teams requests for you with Pulse first, days not updated, the
  evening check-in, goals close to their target date), **Your most efficient day** (the weekday you finish the most
  tasks on, over the last 8 weeks, and your best day this month) and **Today at a glance** (next reminder, today's
  tasks, Teams summary). Tap the greeting to set your name.
- **Backup & restore:** save everything to a file on your phone and load it back (Settings → Backup).
- **Start screen:** choose whether the app opens on Reminders, Daily Sprint or the last one used.
- **Full-screen alert:** turns the screen on and shows over the lock screen, with large **Done** and **Snooze** buttons.
- **Rings in silent mode:** sound plays on the *alarm* stream, so silent or vibrate mode does not mute it, and Android's Do Not Disturb lets alarms through by default. If you grant DND access, DayMate also gets through "Total silence" and then restores your setting. It can raise the alarm volume to a minimum level while ringing.
- **No reminder is lost:**
  - Unanswered alerts ring again (the number of times is configurable), then appear as *Missed*.
  - Reminders that fell due while the phone was off ring a few seconds after it starts, with a "Missed while phone was off" message.
  - If the app was force-stopped, missed reminders are caught when the app is opened again.
  - Alerts that arrive at the same moment are queued.
- **Sounds:** 10 built-in tunes (synthesized by `tools/generate_sounds.py`, so there are no licensing issues), every system alarm, ringtone and notification sound, or any audio file on the phone. Each sound can be previewed.
- **App lock:** fingerprint, face or the phone's PIN/pattern, through `local_auth`. The ringing screen never asks for it.
- **Private:** all data is stored in one JSON file inside the app's private storage. The release APK does not request the INTERNET permission.
- **Easy to use:** large touch targets, a "Larger text" switch, light and dark themes, and a reliability checklist in Settings with tips for specific phone brands.

## Architecture
| Layer | Files |
|---|---|
| Flutter UI | `lib/` (`screens/`, `state.dart`, `native.dart`) |
| Recurrence engine (source of truth) | `android/.../Models.kt` (`Recurrence.next`) |
| Storage | `android/.../Store.kt` |
| AlarmManager `setAlarmClock`, boot/time-change resync, missed detection | `android/.../Scheduler.kt` |
| Foreground ringing service, audio, vibration, DND, queue | `android/.../AlarmService.kt` |
| Full-screen lock-screen alert | `android/.../AlarmActivity.kt`, `res/layout/activity_alarm.xml` |

Scheduling runs natively, so recurring reminders keep re-arming themselves even when the Flutter UI never opens.

## Build & test
```bash
flutter pub get
flutter test                              # Dart unit tests
(cd android && ./gradlew :app:testDebugUnitTest)  # recurrence engine tests
flutter test test_screens --update-goldens        # renders UI screenshots to test_screens/goldens
# Small APKs (about 15-18 MB each instead of one 52 MB file):
flutter build apk --release --split-per-abi --target-platform android-arm,android-arm64 \
  --obfuscate --split-debug-info=build/symbols
#   app-arm64-v8a-release.apk   -> almost every phone from 2017 onwards
#   app-armeabi-v7a-release.apk -> older / budget 32-bit phones
# For the Play Store use: flutter build appbundle --release (Play then delivers only what each phone needs)
```
The release build is signed with the debug key for now. Add your own keystore before publishing.

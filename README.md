# Remindly

An offline Android reminder app (Flutter UI with a native Android alarm engine). Use it for medicines, drinking water, vehicle pollution and insurance renewals, bills, birthdays and anything else.

## Download

**[⬇ Download Remindly for Android](https://github.com/arjundastp/personalhelper/raw/main/downloads/Remindly.apk)** (version 1.3, about 18 MB, Android 8.0 or newer)

- Most phones: [`Remindly.apk`](https://github.com/arjundastp/personalhelper/raw/main/downloads/Remindly.apk)
- Older or very low-cost phones (32-bit): [`Remindly-older-phones.apk`](https://github.com/arjundastp/personalhelper/raw/main/downloads/Remindly-older-phones.apk)

To install: open the downloaded file on your phone. If Android asks, allow your browser or Files app to install apps.
On first start, tap **Allow** so reminders can ring and show full screen.

## Features
- **Reminders that repeat:** once, every N days, chosen weekdays (every N weeks), every N months (for example a pollution certificate every 6 months), yearly, or every few hours within a time window (for example water every 2 h from 8 AM to 10 PM). Each reminder can have an end date.
- **Quick-start templates:** Take medicine, Drink water, Pollution check (PUC), Vehicle insurance, Vehicle service, Pay a bill, Birthday, Doctor visit, Exercise, Water the plants.
- **Sound on/off per reminder:** turn the sound off for a silent reminder that only shows the full-screen alert (and vibrates if vibration is on).
- **Daily Sprint (optional, Settings → Extras → Add Daily Sprint):** a work-day planner on its own bottom tab.
  Add small tasks for the day in a message-style box. A morning nudge comes at 10:30 AM and a full-screen
  "How did today go?" alert at 6:30 PM (both editable, work days only). Mark each task Done, Not done
  (optionally moved to the next work day, labelled "Moved from …") or Paused (goes to the Parked tasks list).
  Also includes past days with a weekly score and a streak. Code: `lib/sprint/`, `android/.../Sprint.kt`.
- **Full-screen alert:** turns the screen on and shows over the lock screen, with large **Done** and **Snooze** buttons.
- **Rings in silent mode:** sound plays on the *alarm* stream, so silent or vibrate mode does not mute it, and Android's Do Not Disturb lets alarms through by default. If you grant DND access, Remindly also gets through "Total silence" and then restores your setting. It can raise the alarm volume to a minimum level while ringing.
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

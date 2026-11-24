// Renders the main screens with sample data into PNGs for visual review.
// Run: flutter test test_screens --update-goldens   (images land in test_screens/goldens/)
import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:remindly/main.dart';
import 'package:remindly/models.dart';
import 'package:remindly/screens/edit_screen.dart';
import 'package:remindly/screens/history_screen.dart';
import 'package:remindly/screens/home_screen.dart';
import 'package:remindly/screens/settings_screen.dart';
import 'package:remindly/screens/sound_picker_screen.dart';
import 'package:remindly/screens/shell.dart';
import 'package:remindly/sprint/review_screen.dart';
import 'package:remindly/sprint/sprint_settings_screen.dart';
import 'package:remindly/state.dart';

Future<void> loadFont(String family, List<String> files) async {
  final loader = FontLoader(family);
  for (final f in files) {
    loader.addFont(Future.value(ByteData.sublistView(File(f).readAsBytesSync())));
  }
  await loader.load();
}

final now = DateTime.now();
int at(Duration d) => now.add(d).millisecondsSinceEpoch;
DateTime todayAt(int h, int m) => DateTime(now.year, now.month, now.day, h, m);

List<Map<String, dynamic>> sampleReminders = [
  {'id': 1, 'title': 'Take blood pressure tablet', 'notes': '1 tablet after breakfast', 'category': 'medicine', 'startDate': isoDate(now), 'hour': 9, 'minute': 0, 'repeat': {'type': 'daily', 'interval': 1}, 'enabled': true, 'nextTrigger': at(const Duration(minutes: 42)), 'snoozeMinutes': 10, 'soundName': 'Soft Bells'},
  {'id': 2, 'title': 'Drink a glass of water', 'category': 'water', 'startDate': isoDate(now), 'hour': 8, 'minute': 0, 'repeat': {'type': 'hourly', 'interval': 120, 'windowEnd': 1320}, 'enabled': true, 'nextTrigger': at(const Duration(hours: 1, minutes: 50))},
  {'id': 3, 'title': 'Renew vehicle pollution certificate', 'category': 'vehicle', 'startDate': isoDate(now.add(const Duration(days: 12))), 'hour': 10, 'minute': 0, 'repeat': {'type': 'monthly', 'interval': 6}, 'enabled': true, 'nextTrigger': at(const Duration(days: 12))},
  {'id': 4, 'title': 'Morning walk', 'category': 'exercise', 'startDate': isoDate(now), 'hour': 6, 'minute': 30, 'repeat': {'type': 'weekly', 'interval': 1, 'weekdays': [1, 2, 3, 4, 5]}, 'soundOn': false, 'enabled': true, 'nextTrigger': at(const Duration(days: 1, hours: 3))},
  {'id': 5, 'title': "Amma's birthday", 'category': 'birthday', 'startDate': isoDate(now.add(const Duration(days: 4))), 'hour': 8, 'minute': 0, 'repeat': {'type': 'yearly', 'interval': 1}, 'enabled': true, 'nextTrigger': at(const Duration(days: 4))},
  {'id': 6, 'title': 'Pay electricity bill', 'category': 'bills', 'startDate': isoDate(now), 'hour': 11, 'minute': 0, 'repeat': {'type': 'monthly', 'interval': 1}, 'enabled': false},
  {'id': 7, 'title': 'Dentist appointment', 'category': 'doctor', 'startDate': isoDate(now.subtract(const Duration(days: 2))), 'hour': 16, 'minute': 0, 'repeat': {'type': 'once'}, 'enabled': false, 'lastFired': at(const Duration(days: -2))},
];

Map<String, dynamic> settings = {
  'defaultSoundUri': 'remindly-tune://gentle_chime', 'defaultSoundName': 'Gentle Chime', 'ringMinutes': 2, 'autoRepeat': 3,
  'snoozeMinutes': 10, 'gradualVolume': true, 'ensureVolume': true, 'minVolume': 70, 'overrideDnd': true, 'vibrate': true,
  'appLock': false, 'themeMode': 'system', 'largeText': false, 'onboarded': true,
};
Map<String, bool> perms = {'notifications': true, 'fullScreen': true, 'exactAlarm': true, 'battery': false, 'dnd': false, 'overlay': false};

List<Map<String, dynamic>> history = [
  {'reminderId': 2, 'title': 'Drink a glass of water', 'category': 'water', 'dueAt': at(const Duration(hours: -2)), 'at': at(const Duration(hours: -1)), 'status': 'missed', 'seen': false},
  {'reminderId': 1, 'title': 'Take blood pressure tablet', 'category': 'medicine', 'dueAt': at(const Duration(hours: -23)), 'at': at(const Duration(hours: -23)), 'status': 'done', 'seen': true},
  {'reminderId': 2, 'title': 'Drink a glass of water', 'category': 'water', 'dueAt': at(const Duration(hours: -4)), 'at': at(const Duration(hours: -4)), 'status': 'snoozed', 'seen': true},
  {'reminderId': 2, 'title': 'Drink a glass of water', 'category': 'water', 'dueAt': at(const Duration(hours: -6)), 'at': at(const Duration(hours: -6)), 'status': 'auto_snoozed', 'seen': true},
];

String iso(DateTime d) => isoDate(d);
DateTime ago(int days) => DateTime(now.year, now.month, now.day).subtract(Duration(days: days));

Map<String, dynamic> sprintJson({bool enabled = true}) {
  var id = 1;
  Map<String, dynamic> t(String text, DateTime d, String status, {String? from, int? movedId}) =>
      {'id': id++, 'text': text, 'date': iso(d), 'status': status, 'from': from, 'movedId': movedId};
  return {
    'enabled': enabled, 'morningOn': true, 'morningMin': 630, 'eveningOn': true, 'eveningMin': 1110,
    'workdays': [1, 2, 3, 4, 5, 6, 7], 'soundOn': true, 'nextId': 100,
    'tasks': [
      t('Reply to client emails', now, 'done'),
      t('Review Ravi’s pull request', now, 'done'),
      t('Prepare slides for 3 PM meeting', now, 'open'),
      t('Fix login bug', now, 'open', from: 'Moved from ${['Mon','Tue','Wed','Thu','Fri','Sat','Sun'][ago(1).weekday - 1]}'),
      t('Send weekly report', now, 'open'),
      t('Fix login bug', ago(1), 'not', movedId: 4),
      t('Update test cases', ago(1), 'done'),
      t('Team sync notes', ago(1), 'done'),
      t('Plan sprint backlog', ago(1), 'done'),
      t('Write release notes', ago(2), 'done'),
      t('Clean up old test data', ago(2), 'paused'),
      t('Call vendor', ago(6), 'done'),
      t('Expense report', ago(6), 'not'),
      for (var d = 7; d < 34; d++)
        if (ago(d).weekday <= 5)
          for (var k = 0; k < 2 + (d * 7) % 4; k++)
            t(k == 0 && d % 3 == 0 ? 'Expense report' : 'Task $d-$k', ago(d),
                ((d * 31 + k * 17) % 10) < (ago(d).weekday == 2 ? 9 : 6) ? 'done' : (((d + k) % 3 == 0) ? 'paused' : 'not')),
    ],
    'parked': [
      {'id': 50, 'text': 'Update the onboarding document', 'pausedOn': iso(ago(1))},
      {'id': 51, 'text': 'Clean up old test data', 'pausedOn': iso(ago(2))},
      {'id': 52, 'text': 'Ask IT about new laptop', 'pausedOn': iso(ago(6))},
    ],
    'reviewed': [iso(ago(1)), iso(ago(2))],
  };
}

bool sprintOn = false;

void mockNative({bool empty = false}) {
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(
    const MethodChannel('remindly/native'),
    (call) async => switch (call.method) {
      'getReminders' => jsonEncode(empty ? [] : sampleReminders),
      'getSettings' => jsonEncode(settings),
      'getSprint' => jsonEncode(sprintJson(enabled: sprintOn)),
      'saveSprint' => null,
      'takeLaunchAction' => null,
      'getHistory' => jsonEncode(empty ? [] : history),
      'permissions' => jsonEncode(perms),
      'deviceInfo' => jsonEncode({'manufacturer': 'Xiaomi', 'sdk': 35}),
      'previewOccurrences' => jsonEncode([for (var i = 1; i <= 3; i++) todayAt(8, 0).add(Duration(hours: 2 * i + 6)).millisecondsSinceEpoch]),
      'getSounds' => jsonEncode({
          'app': [for (final e in bundledSoundNames.entries) {'uri': 'remindly-tune://${e.key}', 'title': e.value, 'group': 'app'}],
          'alarm': [for (final t in ['Argon', 'Barium', 'Carbon', 'Helium', 'Krypton', 'Neon', 'Osmium', 'Platinum']) {'uri': 'content://media/internal/audio/media/$t', 'title': t, 'group': 'alarm'}],
          'ringtone': [], 'notification': [],
        }),
      _ => null,
    },
  );
}

Future<void> shot(WidgetTester tester, String name, Widget home, {ThemeMode mode = ThemeMode.light, bool empty = false}) async {
  mockNative(empty: empty);
  await tester.runAsync(() => AppState.instance.init());
  tester.view.physicalSize = const Size(1080, 2340);
  tester.view.devicePixelRatio = 2.625;
  await tester.pumpWidget(MaterialApp(
    debugShowCheckedModeBanner: false,
    theme: buildTheme(Brightness.light, fontFamily: 'Roboto'),
    darkTheme: buildTheme(Brightness.dark, fontFamily: 'Roboto'),
    themeMode: mode,
    home: home,
  ));
  await tester.runAsync(() => Future.delayed(const Duration(milliseconds: 400)));
  await tester.pumpAndSettle();
  await expectLater(find.byType(MaterialApp), matchesGoldenFile('goldens/$name.png'));
}

void main() {
  setUpAll(() async {
    final fonts = '${Platform.environment['FLUTTER_ROOT'] ?? '/opt/sdk/flutter'}/bin/cache/artifacts/material_fonts';
    await loadFont('Roboto', ['Regular', 'Medium', 'Bold', 'Black', 'Light'].map((w) => '$fonts/Roboto-$w.ttf').toList());
    await loadFont('MaterialIcons', ['$fonts/MaterialIcons-Regular.otf']);
    ui.PlatformDispatcher.instance;
  });

  testWidgets('home', (t) => shot(t, '1_home', const HomeScreen()));
  group('daily sprint', () {
    setUp(() => sprintOn = true);
    tearDown(() => sprintOn = false);
    testWidgets('settings extras', (t) async {
      await shot(t, 's0_settings_extras', const SettingsScreen());
      await t.drag(find.byType(ListView).first, const Offset(0, -1400));
      await t.pumpAndSettle();
      await expectLater(find.byType(MaterialApp), matchesGoldenFile('goldens/s0_settings_extras.png'));
    });
    testWidgets('shell reminders', (t) => shot(t, 's1_shell_reminders', const Shell()));
    testWidgets('sprint today', (t) async {
      await shot(t, 's2_sprint_today', const Shell());
      await t.tap(find.text('Daily Sprint').last);
      await t.pumpAndSettle();
      await expectLater(find.byType(MaterialApp), matchesGoldenFile('goldens/s2_sprint_today.png'));
    });
    testWidgets('review', (t) async {
      await shot(t, 's3_review', ReviewScreen(date: iso(now)));
      await t.tap(find.text('Not done').first);
      await t.tap(find.text('Paused').at(2));
      await t.pumpAndSettle();
      await expectLater(find.byType(MaterialApp), matchesGoldenFile('goldens/s3_review.png'));
    });
    Future<void> sprintTab(WidgetTester t, String name, String tab, {ThemeMode mode = ThemeMode.light, bool thirty = false}) async {
      await shot(t, name, const Shell(), mode: mode);
      await t.tap(find.text('Daily Sprint').last);
      await t.pumpAndSettle();
      await t.tap(find.text(tab));
      await t.pumpAndSettle();
      if (thirty) {
        await t.tap(find.text('30 days'));
        await t.pumpAndSettle();
      }
      await expectLater(find.byType(MaterialApp), matchesGoldenFile('goldens/$name.png'));
    }
    testWidgets('parked', (t) => sprintTab(t, 's4_parked', 'PARKED'));
    testWidgets('history', (t) => sprintTab(t, 's5_history', 'HISTORY'));
    testWidgets('insights', (t) => sprintTab(t, 's7_insights', 'INSIGHTS'));
    testWidgets('insights 30 dark', (t) => sprintTab(t, 's8_insights_30_dark', 'INSIGHTS', mode: ThemeMode.dark, thirty: true));
    testWidgets('insights scrolled', (t) async {
      await sprintTab(t, 's9_insights_lower', 'INSIGHTS');
      await t.drag(find.byType(ListView).last, const Offset(0, -700));
      await t.pumpAndSettle();
      await expectLater(find.byType(MaterialApp), matchesGoldenFile('goldens/s9_insights_lower.png'));
    });
    testWidgets('sprint settings', (t) => shot(t, 's6_sprint_settings', const SprintSettingsScreen()));
  });
  testWidgets('home dark', (t) => shot(t, '2_home_dark', const HomeScreen(), mode: ThemeMode.dark));
  testWidgets('home empty', (t) => shot(t, '3_home_empty', const HomeScreen(), empty: true));
  testWidgets('new water', (t) => shot(t, '4_new_water', EditScreen(template: templates[1])));
  testWidgets('edit weekly', (t) async {
    await shot(t, '5_edit_weekly', EditScreen(reminder: Reminder.fromJson(sampleReminders[3])));
  });
  testWidgets('sounds', (t) => shot(t, '6_sounds', const SoundPickerScreen(selectedUri: 'remindly-tune://soft_bells')));
  testWidgets('settings', (t) => shot(t, '7_settings', const SettingsScreen()));
  testWidgets('history', (t) => shot(t, '8_history', const HistoryScreen()));
  testWidgets('new blank', (t) => shot(t, '9_new_blank', const EditScreen()));
  testWidgets('repeat sheet', (t) async {
    await shot(t, '10_repeat_sheet', EditScreen(reminder: Reminder.fromJson(sampleReminders[3])));
    await expectLater(find.byType(MaterialApp), matchesGoldenFile('goldens/5_edit_weekly.png'));
    await t.tap(find.text('Repeat'));
    await t.pumpAndSettle();
    await expectLater(find.byType(MaterialApp), matchesGoldenFile('goldens/10_repeat_sheet.png'));
  });
  testWidgets('long press', (t) async {
    await shot(t, '11_long_press', const HomeScreen());
    await t.longPress(find.text('Morning walk'));
    await t.pumpAndSettle();
    await expectLater(find.byType(MaterialApp), matchesGoldenFile('goldens/11_long_press.png'));
  });
}

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

void mockNative({bool empty = false}) {
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(
    const MethodChannel('remindly/native'),
    (call) async => switch (call.method) {
      'getReminders' => jsonEncode(empty ? [] : sampleReminders),
      'getSettings' => jsonEncode(settings),
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

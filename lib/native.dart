import 'dart:convert';

import 'package:flutter/services.dart';

import 'models.dart';

/// Thin wrapper over the Android side (MainActivity.kt). All payloads are JSON strings.
class Native {
  static const _ch = MethodChannel('remindly/native');

  static void setHandler(Future<dynamic> Function(MethodCall call) handler) => _ch.setMethodCallHandler(handler);

  static Future<void> sync() => _ch.invokeMethod('sync');

  static Future<List<Reminder>> reminders() async {
    final s = await _ch.invokeMethod<String>('getReminders');
    return (jsonDecode(s ?? '[]') as List).map((e) => Reminder.fromJson(e as Map<String, dynamic>)).toList();
  }

  static Future<Reminder> save(Reminder r) async {
    final s = await _ch.invokeMethod<String>('saveReminder', jsonEncode(r.toJson()));
    return Reminder.fromJson(jsonDecode(s!) as Map<String, dynamic>);
  }

  static Future<void> delete(int id) => _ch.invokeMethod('deleteReminder', id);

  static Future<void> setEnabled(int id, bool enabled) =>
      _ch.invokeMethod('setEnabled', {'id': id, 'enabled': enabled});

  static Future<List<DateTime>> preview(Reminder r, {int count = 3}) async {
    final s = await _ch.invokeMethod<String>('previewOccurrences', {'reminder': jsonEncode(r.toJson()), 'count': count});
    return (jsonDecode(s ?? '[]') as List).map((e) => DateTime.fromMillisecondsSinceEpoch((e as num).toInt())).toList();
  }

  static Future<Map<String, dynamic>> settings() async =>
      jsonDecode(await _ch.invokeMethod<String>('getSettings') ?? '{}') as Map<String, dynamic>;

  static Future<void> saveSettings(Map<String, dynamic> update) => _ch.invokeMethod('saveSettings', jsonEncode(update));

  static Future<List<HistoryEntry>> history() async {
    final s = await _ch.invokeMethod<String>('getHistory');
    return (jsonDecode(s ?? '[]') as List).map((e) => HistoryEntry.fromJson(e as Map<String, dynamic>)).toList();
  }

  static Future<void> markHistorySeen() => _ch.invokeMethod('markHistorySeen');
  static Future<void> clearHistory() => _ch.invokeMethod('clearHistory');

  static Future<Map<String, List<SoundOption>>> sounds() async {
    final m = jsonDecode(await _ch.invokeMethod<String>('getSounds') ?? '{}') as Map<String, dynamic>;
    return m.map((k, v) => MapEntry(k, (v as List).map((e) => SoundOption.fromJson(e as Map<String, dynamic>)).toList()));
  }

  static Future<bool> previewSound(String uri) async => await _ch.invokeMethod<bool>('previewSound', uri) ?? false;
  static Future<void> stopPreview() => _ch.invokeMethod('stopPreview');

  static Future<SoundOption?> pickAudioFile() async {
    final s = await _ch.invokeMethod<String>('pickAudioFile');
    return s == null ? null : SoundOption.fromJson(jsonDecode(s) as Map<String, dynamic>);
  }

  static Future<void> testAlarm({int seconds = 5}) => _ch.invokeMethod('testAlarm', seconds);

  static Future<Map<String, bool>> permissions() async {
    final m = jsonDecode(await _ch.invokeMethod<String>('permissions') ?? '{}') as Map<String, dynamic>;
    return m.map((k, v) => MapEntry(k, v as bool));
  }

  static Future<void> requestPermission(String name) => _ch.invokeMethod('requestPermission', name);

  static Future<Map<String, dynamic>> deviceInfo() async =>
      jsonDecode(await _ch.invokeMethod<String>('deviceInfo') ?? '{}') as Map<String, dynamic>;
}

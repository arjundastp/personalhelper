import 'dart:async';

import 'package:material_ui/material_ui.dart';

import 'models.dart';
import 'native.dart';

/// App-wide state. The Android side is the source of truth; this mirrors it for the UI.
class AppState extends ChangeNotifier {
  AppState._();
  static final AppState instance = AppState._();

  List<Reminder> reminders = [];
  Map<String, dynamic> settings = {};
  List<HistoryEntry> history = [];
  Map<String, bool> permissions = {};
  String manufacturer = '';
  bool loaded = false;

  /// Asked by native when the user taps a "missed reminder" notification.
  final openHistoryRequests = StreamController<void>.broadcast();

  Timer? _debounce;

  Future<void> init() async {
    Native.setHandler((call) async {
      switch (call.method) {
        case 'changed':
          _debounce?.cancel();
          _debounce = Timer(const Duration(milliseconds: 150), refresh);
        case 'openHistory':
          openHistoryRequests.add(null);
      }
      return null;
    });
    try {
      await Native.sync();
      manufacturer = ((await Native.deviceInfo())['manufacturer'] as String? ?? '').toLowerCase();
    } catch (_) {}
    await refresh();
  }

  Future<void> refresh() async {
    try {
      final results = await Future.wait([Native.reminders(), Native.settings(), Native.history(), Native.permissions()]);
      reminders = results[0] as List<Reminder>;
      settings = results[1] as Map<String, dynamic>;
      history = results[2] as List<HistoryEntry>;
      permissions = results[3] as Map<String, bool>;
    } catch (_) {}
    loaded = true;
    notifyListeners();
  }

  Future<void> refreshPermissions() async {
    permissions = await Native.permissions();
    notifyListeners();
  }

  // ---- reminders ----

  Future<Reminder> save(Reminder r) async {
    final saved = await Native.save(r);
    await refresh();
    return saved;
  }

  Future<void> delete(int id) async {
    await Native.delete(id);
    await refresh();
  }

  Future<void> setEnabled(Reminder r, bool on) async {
    await Native.setEnabled(r.id, on);
    await refresh();
  }

  // ---- settings ----

  T setting<T>(String key, T fallback) {
    final v = settings[key];
    return v is T ? v : fallback;
  }

  Future<void> updateSettings(Map<String, dynamic> update) async {
    settings = {...settings, ...update};
    notifyListeners();
    await Native.saveSettings(update);
  }

  ThemeMode get themeMode => switch (setting('themeMode', 'system')) {
        'light' => ThemeMode.light,
        'dark' => ThemeMode.dark,
        _ => ThemeMode.system,
      };

  // ---- derived ----

  int get unseenMissed => history.where((h) => h.status == 'missed' && !h.seen).length;

  /// Permissions without which alerts may not appear at all.
  List<String> get missingCritical =>
      ['notifications', 'fullScreen', 'exactAlarm'].where((k) => permissions[k] == false).toList();

  List<Reminder> get upcoming {
    final list = reminders.where((r) => r.enabled && r.nextAlert != null).toList()
      ..sort((a, b) => a.nextAlert!.compareTo(b.nextAlert!));
    return list;
  }

  List<Reminder> get inactive => reminders.where((r) => !r.enabled || r.nextAlert == null).toList()
    ..sort((a, b) => a.title.toLowerCase().compareTo(b.title.toLowerCase()));
}

import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:material_ui/material_ui.dart';

import '../models.dart' show isoDate, dateOnly;

/// Status of a planned task. `open` = not answered yet.
abstract class TaskStatus {
  static const open = 'open';
  static const done = 'done';
  static const notDone = 'not';
  static const paused = 'paused';
}

class SprintTask {
  final int id;
  String text;
  String date; // yyyy-MM-dd
  String status;
  String? from; // "Moved from Mon" / "From parked" / "From Mon"
  int? movedId; // copy created on the next work day when "Not done" + move
  int? parkedId; // entry created in the parked list when "Paused"

  SprintTask({required this.id, required this.text, required this.date, this.status = TaskStatus.open, this.from, this.movedId, this.parkedId});

  Map<String, dynamic> toJson() =>
      {'id': id, 'text': text, 'date': date, 'status': status, 'from': from, 'movedId': movedId, 'parkedId': parkedId};

  factory SprintTask.fromJson(Map<String, dynamic> j) => SprintTask(
        id: (j['id'] as num).toInt(),
        text: j['text'] as String? ?? '',
        date: j['date'] as String? ?? isoDate(DateTime.now()),
        status: j['status'] as String? ?? TaskStatus.open,
        from: j['from'] as String?,
        movedId: (j['movedId'] as num?)?.toInt(),
        parkedId: (j['parkedId'] as num?)?.toInt(),
      );
}

class ParkedTask {
  final int id;
  String text;
  final String pausedOn; // yyyy-MM-dd

  ParkedTask({required this.id, required this.text, required this.pausedOn});

  Map<String, dynamic> toJson() => {'id': id, 'text': text, 'pausedOn': pausedOn};

  factory ParkedTask.fromJson(Map<String, dynamic> j) => ParkedTask(
        id: (j['id'] as num).toInt(),
        text: j['text'] as String? ?? '',
        pausedOn: j['pausedOn'] as String? ?? isoDate(DateTime.now()),
      );
}

/// Answer given on the review screen for one task.
class ReviewAnswer {
  final String status;
  final bool move;
  const ReviewAnswer(this.status, {this.move = true});
}

/// Daily Sprint: the optional work-day planner. Everything is stored on the phone, in the same
/// file as reminders (native side, key "sprint"); the native side reads the settings and today's
/// counts to schedule the morning nudge and the evening full-screen check-in.
class SprintState extends ChangeNotifier {
  SprintState({MethodChannel? channel}) : _ch = channel ?? const MethodChannel('remindly/native');
  static final SprintState instance = SprintState();

  final MethodChannel _ch;

  bool enabled = false;
  bool morningOn = true;
  int morningMin = 10 * 60 + 30; // 10:30 AM
  bool eveningOn = true;
  int eveningMin = 18 * 60 + 30; // 6:30 PM
  List<int> workdays = [1, 2, 3, 4, 5];
  bool soundOn = true;
  String? soundUri;
  String? soundName;
  int nextId = 1;
  List<SprintTask> tasks = [];
  List<ParkedTask> parked = [];
  Set<String> reviewed = {};

  /// Clock used for "today"; replaceable in tests.
  DateTime Function() now = DateTime.now;

  String get today => isoDate(now());

  // ---------------- persistence ----------------

  Map<String, dynamic> toJson() => {
        'enabled': enabled,
        'morningOn': morningOn,
        'morningMin': morningMin,
        'eveningOn': eveningOn,
        'eveningMin': eveningMin,
        'workdays': workdays,
        'soundOn': soundOn,
        'soundUri': soundUri,
        'soundName': soundName,
        'nextId': nextId,
        'tasks': tasks.map((t) => t.toJson()).toList(),
        'parked': parked.map((p) => p.toJson()).toList(),
        'reviewed': reviewed.toList()..sort(),
      };

  void fromJson(Map<String, dynamic> j) {
    enabled = j['enabled'] as bool? ?? false;
    morningOn = j['morningOn'] as bool? ?? true;
    morningMin = (j['morningMin'] as num?)?.toInt() ?? 10 * 60 + 30;
    eveningOn = j['eveningOn'] as bool? ?? true;
    eveningMin = (j['eveningMin'] as num?)?.toInt() ?? 18 * 60 + 30;
    workdays = ((j['workdays'] as List?) ?? const [1, 2, 3, 4, 5]).map((e) => (e as num).toInt()).toList();
    soundOn = j['soundOn'] as bool? ?? true;
    soundUri = j['soundUri'] as String?;
    soundName = j['soundName'] as String?;
    nextId = (j['nextId'] as num?)?.toInt() ?? 1;
    tasks = ((j['tasks'] as List?) ?? const []).map((e) => SprintTask.fromJson(e as Map<String, dynamic>)).toList();
    parked = ((j['parked'] as List?) ?? const []).map((e) => ParkedTask.fromJson(e as Map<String, dynamic>)).toList();
    reviewed = ((j['reviewed'] as List?) ?? const []).map((e) => e as String).toSet();
  }

  Future<void> load() async {
    try {
      final s = await _ch.invokeMethod<String>('getSprint');
      fromJson(jsonDecode(s ?? '{}') as Map<String, dynamic>);
    } catch (_) {}
    notifyListeners();
  }

  Future<void> save() async {
    notifyListeners();
    try {
      await _ch.invokeMethod('saveSprint', jsonEncode(toJson()));
    } catch (_) {}
  }

  int _newId() => nextId++;

  // ---------------- settings ----------------

  Future<void> setEnabled(bool on) async {
    enabled = on;
    await save();
  }

  Future<void> update(void Function(SprintState s) change) async {
    change(this);
    await save();
  }

  // ---------------- day plan ----------------

  List<SprintTask> tasksFor(String date) => tasks.where((t) => t.date == date).toList();

  int openToday() => tasksFor(today).where((t) => t.status == TaskStatus.open).length;

  SprintTask? byId(int id) {
    for (final t in tasks) {
      if (t.id == id) return t;
    }
    return null;
  }

  Future<void> add(String date, String text, {String? from}) async {
    final t = text.trim();
    if (t.isEmpty) return;
    tasks.add(SprintTask(id: _newId(), text: t, date: date, from: from));
    await save();
  }

  /// Tapping the circle: done <-> open.
  Future<void> toggleDone(int id) async {
    final t = byId(id);
    if (t == null) return;
    _undoSideEffects(t);
    t.status = t.status == TaskStatus.done ? TaskStatus.open : TaskStatus.done;
    await save();
  }

  Future<void> rename(int id, String text) async {
    final t = byId(id);
    if (t == null || text.trim().isEmpty) return;
    t.text = text.trim();
    await save();
  }

  Future<void> delete(int id) async {
    final t = byId(id);
    if (t == null) return;
    _undoSideEffects(t);
    tasks.remove(t);
    await save();
  }

  /// Pause a task from the list: it moves to the parked list.
  Future<void> pause(int id) async {
    final t = byId(id);
    if (t == null) return;
    _apply(t, const ReviewAnswer(TaskStatus.paused));
    await save();
  }

  /// Saves the evening answers for [date].
  Future<void> review(String date, Map<int, ReviewAnswer> answers) async {
    for (final e in answers.entries) {
      final t = byId(e.key);
      if (t != null) _apply(t, e.value);
    }
    reviewed.add(date);
    await save();
  }

  void _apply(SprintTask t, ReviewAnswer a) {
    _undoSideEffects(t);
    t.status = a.status;
    if (a.status == TaskStatus.notDone && a.move) {
      final next = isoDate(nextWorkday(DateTime.parse(t.date)));
      final copy = SprintTask(id: _newId(), text: t.text, date: next, from: 'Moved from ${_dayName(t.date)}');
      tasks.add(copy);
      t.movedId = copy.id;
    } else if (a.status == TaskStatus.paused) {
      final p = ParkedTask(id: _newId(), text: t.text, pausedOn: t.date);
      parked.insert(0, p);
      t.parkedId = p.id;
    }
  }

  /// Changing an answer again must not leave the old copy / parked entry behind.
  void _undoSideEffects(SprintTask t) {
    if (t.movedId != null) {
      final copy = byId(t.movedId!);
      // Only remove the copy if it was not worked on yet.
      if (copy != null && copy.status == TaskStatus.open) tasks.remove(copy);
      t.movedId = null;
    }
    if (t.parkedId != null) {
      parked.removeWhere((p) => p.id == t.parkedId);
      t.parkedId = null;
    }
  }

  // ---------------- unfinished days ----------------

  /// The most recent earlier day (last 14 days) whose tasks were never answered.
  String? get unansweredDay {
    final cutoff = isoDate(now().subtract(const Duration(days: 14)));
    final days = tasks
        .where((t) => t.status == TaskStatus.open && t.date.compareTo(today) < 0 && t.date.compareTo(cutoff) >= 0)
        .map((t) => t.date)
        .toSet()
        .toList()
      ..sort();
    return days.isEmpty ? null : days.last;
  }

  /// "Add to today" on the banner: unanswered tasks of [date] become Not done and are copied to today.
  Future<void> carryToToday(String date) async {
    for (final t in tasksFor(date).where((t) => t.status == TaskStatus.open)) {
      t.status = TaskStatus.notDone;
      final copy = SprintTask(id: _newId(), text: t.text, date: today, from: 'From ${_dayName(date)}');
      tasks.add(copy);
      t.movedId = copy.id;
    }
    await save();
  }

  // ---------------- parked ----------------

  Future<void> park(String text) async {
    final t = text.trim();
    if (t.isEmpty) return;
    parked.insert(0, ParkedTask(id: _newId(), text: t, pausedOn: today));
    await save();
  }

  /// Takes a parked task off the list and adds it to today's plan.
  Future<void> bringBack(int parkedId) async {
    final p = parked.where((x) => x.id == parkedId).firstOrNull;
    if (p == null) return;
    parked.remove(p);
    _forgetParkedLink(parkedId);
    tasks.add(SprintTask(id: _newId(), text: p.text, date: today, from: 'From parked'));
    await save();
  }

  /// Removes a parked task ("Done" or "Delete" from its menu).
  Future<void> removeParked(int parkedId) async {
    parked.removeWhere((x) => x.id == parkedId);
    _forgetParkedLink(parkedId);
    await save();
  }

  void _forgetParkedLink(int parkedId) {
    for (final t in tasks) {
      if (t.parkedId == parkedId) t.parkedId = null;
    }
  }

  // ---------------- history ----------------

  /// Days that had a plan, newest first (today included).
  List<String> get pastDays {
    final d = tasks.map((t) => t.date).where((d) => d.compareTo(today) <= 0).toSet().toList()..sort();
    return d.reversed.toList();
  }

  ({int planned, int done}) weekStats() {
    final n = dateOnly(now());
    final monday = isoDate(n.subtract(Duration(days: n.weekday - 1)));
    final week = tasks.where((t) => t.date.compareTo(monday) >= 0 && t.date.compareTo(today) <= 0);
    return (planned: week.length, done: week.where((t) => t.status == TaskStatus.done).length);
  }

  /// Planned days in a row (going back from today, or yesterday if today is not answered yet)
  /// where every task got an answer. Days without a plan don't break the streak.
  int get streak {
    var count = 0;
    var day = dateOnly(now());
    final firstDay = tasks.isEmpty ? today : (tasks.map((t) => t.date).toList()..sort()).first;
    var skippedToday = false;
    while (isoDate(day).compareTo(firstDay) >= 0) {
      final list = tasksFor(isoDate(day));
      if (list.isNotEmpty) {
        final answered = list.every((t) => t.status != TaskStatus.open);
        if (answered) {
          count++;
        } else if (isoDate(day) == today && !skippedToday) {
          skippedToday = true; // today is still in progress
        } else {
          break;
        }
      }
      day = day.subtract(const Duration(days: 1));
    }
    return count;
  }

  // ---------------- helpers ----------------

  DateTime nextWorkday(DateTime from) {
    final days = workdays.isEmpty ? [1, 2, 3, 4, 5, 6, 7] : workdays;
    var d = dateOnly(from);
    for (var i = 0; i < 7; i++) {
      d = d.add(const Duration(days: 1));
      if (days.contains(d.weekday)) return d;
    }
    return dateOnly(from).add(const Duration(days: 1));
  }

  String _dayName(String date) => DateFormat('EEE').format(DateTime.parse(date));
}

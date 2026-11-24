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
  static const partial = 'partial'; // partly done; the rest can continue on the next work day
}

class SprintTask {
  final int id;
  String text;
  String date; // yyyy-MM-dd
  String status;
  String? from; // "Moved from Mon" / "From parked" / "From Mon"
  int? movedId; // copy created on the next work day when "Not done" + move
  int? parkedId; // entry created in the parked list when "Paused"
  String? note; // free text, e.g. what was finished and what is left

  SprintTask({
    required this.id,
    required this.text,
    required this.date,
    this.status = TaskStatus.open,
    this.from,
    this.movedId,
    this.parkedId,
    this.note,
  });

  Map<String, dynamic> toJson() =>
      {'id': id, 'text': text, 'date': date, 'status': status, 'from': from, 'movedId': movedId, 'parkedId': parkedId, 'note': note};

  factory SprintTask.fromJson(Map<String, dynamic> j) => SprintTask(
        id: (j['id'] as num).toInt(),
        text: j['text'] as String? ?? '',
        date: j['date'] as String? ?? isoDate(DateTime.now()),
        status: j['status'] as String? ?? TaskStatus.open,
        from: j['from'] as String?,
        movedId: (j['movedId'] as num?)?.toInt(),
        parkedId: (j['parkedId'] as num?)?.toInt(),
        note: j['note'] as String?,
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

/// A day off. type: `leave` (full day), `half` (half-day leave) or `holiday` (public holiday).
class LeaveDay {
  final String type;
  final String? note;
  const LeaveDay(this.type, {this.note});

  bool get fullDayOff => type != LeaveType.half;

  String get label => switch (type) {
        LeaveType.half => 'Half-day leave',
        LeaveType.holiday => 'Holiday',
        _ => 'On leave',
      };

  Map<String, dynamic> toJson() => {'type': type, 'note': note};
  factory LeaveDay.fromJson(Map<String, dynamic> j) => LeaveDay(j['type'] as String? ?? LeaveType.leave, note: j['note'] as String?);
}

/// A dated progress update on a goal.
class GoalNote {
  final String date; // yyyy-MM-dd
  final String text;
  final int? progress; // progress (0-100) recorded with this note, if changed
  const GoalNote(this.date, this.text, {this.progress});

  Map<String, dynamic> toJson() => {'date': date, 'text': text, 'progress': progress};
  factory GoalNote.fromJson(Map<String, dynamic> j) =>
      GoalNote(j['date'] as String, j['text'] as String? ?? '', progress: (j['progress'] as num?)?.toInt());
}

abstract class GoalStatus {
  static const active = 'active';
  static const done = 'done';
  static const dropped = 'dropped';
}

/// A long-term goal (weeks or months), tracked with a 0-100 progress and progress notes.
class Goal {
  final int id;
  String title;
  String why;
  String? targetDate; // yyyy-MM-dd
  int progress;
  String status;
  final String createdOn;
  List<GoalNote> notes; // newest first

  Goal({
    required this.id,
    required this.title,
    this.why = '',
    this.targetDate,
    this.progress = 0,
    this.status = GoalStatus.active,
    required this.createdOn,
    List<GoalNote>? notes,
  }) : notes = notes ?? [];

  String? get lastUpdate => notes.isEmpty ? null : notes.first.date;

  Map<String, dynamic> toJson() => {
        'id': id,
        'title': title,
        'why': why,
        'targetDate': targetDate,
        'progress': progress,
        'status': status,
        'createdOn': createdOn,
        'notes': notes.map((n) => n.toJson()).toList(),
      };

  factory Goal.fromJson(Map<String, dynamic> j) => Goal(
        id: (j['id'] as num).toInt(),
        title: j['title'] as String? ?? '',
        why: j['why'] as String? ?? '',
        targetDate: j['targetDate'] as String?,
        progress: (j['progress'] as num?)?.toInt() ?? 0,
        status: j['status'] as String? ?? GoalStatus.active,
        createdOn: j['createdOn'] as String? ?? isoDate(DateTime.now()),
        notes: ((j['notes'] as List?) ?? const []).map((e) => GoalNote.fromJson(Map<String, dynamic>.from(e as Map))).toList(),
      );
}

/// Something worth showing in a review meeting.
class Achievement {
  final int id;
  String title;
  String details;
  String date; // yyyy-MM-dd
  String category;
  int? goalId;

  Achievement({required this.id, required this.title, this.details = '', required this.date, this.category = 'delivery', this.goalId});

  Map<String, dynamic> toJson() => {'id': id, 'title': title, 'details': details, 'date': date, 'category': category, 'goalId': goalId};

  factory Achievement.fromJson(Map<String, dynamic> j) => Achievement(
        id: (j['id'] as num).toInt(),
        title: j['title'] as String? ?? '',
        details: j['details'] as String? ?? '',
        date: j['date'] as String? ?? isoDate(DateTime.now()),
        category: j['category'] as String? ?? 'delivery',
        goalId: (j['goalId'] as num?)?.toInt(),
      );
}

abstract class LeaveType {
  static const leave = 'leave';
  static const half = 'half';
  static const holiday = 'holiday';
}

/// Answer given on the review screen for one task.
class ReviewAnswer {
  final String status;
  final bool move; // Not done / Partly done: continue on the next work day
  final String? note; // null = keep the task's current note
  const ReviewAnswer(this.status, {this.move = true, this.note});
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
  Map<String, LeaveDay> leaves = {};
  String? startedOn; // first day Daily Sprint was used; reports count from here
  List<Goal> goals = [];
  List<Achievement> achievements = [];

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
        'leaves': {for (final e in leaves.entries) e.key: e.value.toJson()},
        'startedOn': startedOn,
        'goals': goals.map((g) => g.toJson()).toList(),
        'achievements': achievements.map((a) => a.toJson()).toList(),
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
    leaves = ((j['leaves'] as Map?) ?? const {})
        .map((k, v) => MapEntry(k as String, LeaveDay.fromJson(Map<String, dynamic>.from(v as Map))));
    startedOn = j['startedOn'] as String?;
    goals = ((j['goals'] as List?) ?? const []).map((e) => Goal.fromJson(Map<String, dynamic>.from(e as Map))).toList();
    achievements =
        ((j['achievements'] as List?) ?? const []).map((e) => Achievement.fromJson(Map<String, dynamic>.from(e as Map))).toList();
  }

  // ---------------- goals ----------------

  Goal? goalById(int? id) => id == null ? null : goals.where((g) => g.id == id).firstOrNull;

  Future<Goal> addGoal(String title, {String why = '', String? targetDate}) async {
    final g = Goal(id: _newId(), title: title.trim(), why: why.trim(), targetDate: targetDate, createdOn: today);
    goals.add(g);
    await save();
    return g;
  }

  /// Adds a progress note; [progress] (0-100) updates the goal's progress when given.
  /// Reaching 100 marks the goal completed.
  Future<void> addGoalNote(int goalId, String text, {int? progress}) async {
    final g = goalById(goalId);
    if (g == null || (text.trim().isEmpty && progress == null)) return;
    final p = progress?.clamp(0, 100);
    g.notes.insert(0, GoalNote(today, text.trim(), progress: p));
    if (p != null) {
      g.progress = p;
      if (p >= 100) g.status = GoalStatus.done;
    }
    await save();
  }

  Future<void> deleteGoalNote(int goalId, int index) async {
    final g = goalById(goalId);
    if (g == null || index < 0 || index >= g.notes.length) return;
    g.notes.removeAt(index);
    await save();
  }

  Future<void> setGoalStatus(int goalId, String status) async {
    final g = goalById(goalId);
    if (g == null) return;
    g.status = status;
    if (status == GoalStatus.done) g.progress = 100;
    await save();
  }

  Future<void> deleteGoal(int goalId) async {
    goals.removeWhere((g) => g.id == goalId);
    for (final a in achievements) {
      if (a.goalId == goalId) a.goalId = null;
    }
    await save();
  }

  // ---------------- achievements ----------------

  Future<void> addAchievement(String title, {String details = '', String? date, String category = 'delivery', int? goalId}) async {
    if (title.trim().isEmpty) return;
    achievements.add(Achievement(
      id: _newId(),
      title: title.trim(),
      details: details.trim(),
      date: date ?? today,
      category: category,
      goalId: goalId,
    ));
    await save();
  }

  Future<void> deleteAchievement(int id) async {
    achievements.removeWhere((a) => a.id == id);
    await save();
  }

  /// Achievements dated within [from]..[to] (inclusive), newest first.
  List<Achievement> achievementsBetween(String from, String to) =>
      achievements.where((a) => a.date.compareTo(from) >= 0 && a.date.compareTo(to) <= 0).toList()
        ..sort((a, b) => b.date.compareTo(a.date) != 0 ? b.date.compareTo(a.date) : b.id.compareTo(a.id));

  /// First day that counts for reports: when Daily Sprint was turned on, or the earliest
  /// planned / leave day if that is earlier (e.g. leave entered for past days).
  String get firstDay {
    final dates = [?startedOn, ...tasks.map((t) => t.date), ...leaves.keys];
    if (dates.isEmpty) return today;
    dates.sort();
    return dates.first;
  }

  // ---------------- leave ----------------

  LeaveDay? leaveOn(String date) => leaves[date];

  /// Full day off (leave or holiday): no prompts, tasks don't move onto it.
  bool isOff(String date) => leaves[date]?.fullDayOff ?? false;

  /// Marks [date] as leave / half day / holiday. On a full day off, unanswered tasks of that day
  /// move to the next work day (labelled "Moved from …").
  Future<int> setLeave(String date, String type, {String? note}) async {
    leaves[date] = LeaveDay(type, note: (note == null || note.trim().isEmpty) ? null : note.trim());
    var moved = 0;
    if (type != LeaveType.half) {
      for (final t in tasksFor(date).where((t) => t.status == TaskStatus.open).toList()) {
        _apply(t, const ReviewAnswer(TaskStatus.notDone));
        moved++;
      }
    }
    await save();
    return moved;
  }

  Future<void> clearLeave(String date) async {
    leaves.remove(date);
    await save();
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
    if (on) startedOn ??= today;
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

  /// Sets or clears (empty text) the task's note.
  Future<void> setNote(int id, String? text) async {
    final t = byId(id);
    if (t == null) return;
    t.note = _cleanNote(text);
    await save();
  }

  /// Marks a task partly done with an optional note; [move] continues it on the next work day.
  Future<void> markPartial(int id, {String? note, bool move = true}) async {
    final t = byId(id);
    if (t == null) return;
    _apply(t, ReviewAnswer(TaskStatus.partial, move: move, note: note ?? ''));
    await save();
  }

  static String? _cleanNote(String? text) => (text == null || text.trim().isEmpty) ? null : text.trim();

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
    if (a.note != null) t.note = _cleanNote(a.note);
    if ((a.status == TaskStatus.notDone || a.status == TaskStatus.partial) && a.move) {
      final next = isoDate(nextWorkday(DateTime.parse(t.date)));
      final partial = a.status == TaskStatus.partial;
      final copy = SprintTask(
        id: _newId(),
        text: t.text,
        date: next,
        from: '${partial ? 'Continued' : 'Moved'} from ${_dayName(t.date)}',
        note: partial ? t.note : null, // where you left off
      );
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
    final d = {...tasks.map((t) => t.date), ...leaves.keys}.where((d) => d.compareTo(today) <= 0).toList()..sort();
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
    for (var i = 0; i < 60; i++) {
      d = d.add(const Duration(days: 1));
      if (days.contains(d.weekday) && !isOff(isoDate(d))) return d;
    }
    return dateOnly(from).add(const Duration(days: 1));
  }

  String _dayName(String date) => DateFormat('EEE').format(DateTime.parse(date));
}

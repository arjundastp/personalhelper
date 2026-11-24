import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:remindly/sprint/review_export.dart';
import 'package:remindly/sprint/sprint_state.dart';
import 'package:remindly/sprint/sprint_stats.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const ch = MethodChannel('remindly/sprint-test');
  final saved = <String>[];
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(ch, (call) async {
    if (call.method == 'saveSprint') saved.add(call.arguments as String);
    if (call.method == 'getSprint') return '{}';
    return null;
  });

  // Tuesday 24 Nov 2026, 11:00
  SprintState fresh({DateTime? at}) => SprintState(channel: ch)..now = () => at ?? DateTime(2026, 11, 24, 11);

  test('not done + move creates a labelled copy on the next work day', () async {
    final s = fresh();
    await s.add('2026-11-24', 'Fix login bug');
    final id = s.tasks.single.id;
    await s.review('2026-11-24', {id: const ReviewAnswer(TaskStatus.notDone)});
    final copy = s.tasksFor('2026-11-25').single;
    expect(copy.text, 'Fix login bug');
    expect(copy.from, 'Moved from Tue');
    expect(copy.status, TaskStatus.open);
    expect(s.reviewed, contains('2026-11-24'));
  });

  test('Friday tasks move to Monday', () async {
    final s = fresh(at: DateTime(2026, 11, 27, 18));
    await s.add('2026-11-27', 'Report');
    await s.review('2026-11-27', {s.tasks.single.id: const ReviewAnswer(TaskStatus.notDone)});
    expect(s.tasksFor('2026-11-30').single.from, 'Moved from Fri');
  });

  test('not done without move creates no copy', () async {
    final s = fresh();
    await s.add('2026-11-24', 'A');
    await s.review('2026-11-24', {s.tasks.single.id: const ReviewAnswer(TaskStatus.notDone, move: false)});
    expect(s.tasks.length, 1);
  });

  test('paused goes to parked; changing the answer removes it again', () async {
    final s = fresh();
    await s.add('2026-11-24', 'Docs');
    final id = s.tasks.single.id;
    await s.review('2026-11-24', {id: const ReviewAnswer(TaskStatus.paused)});
    expect(s.parked.single.text, 'Docs');
    await s.review('2026-11-24', {id: const ReviewAnswer(TaskStatus.done)});
    expect(s.parked, isEmpty);
    expect(s.byId(id)!.status, TaskStatus.done);
  });

  test('changing a moved answer removes the untouched copy', () async {
    final s = fresh();
    await s.add('2026-11-24', 'A');
    final id = s.tasks.single.id;
    await s.review('2026-11-24', {id: const ReviewAnswer(TaskStatus.notDone)});
    expect(s.tasks.length, 2);
    await s.review('2026-11-24', {id: const ReviewAnswer(TaskStatus.done)});
    expect(s.tasks.length, 1);
  });

  test('bring back from parked adds to today', () async {
    final s = fresh();
    await s.park('Ask IT about laptop');
    await s.bringBack(s.parked.single.id);
    expect(s.parked, isEmpty);
    final t = s.tasksFor('2026-11-24').single;
    expect(t.from, 'From parked');
  });

  test('unanswered earlier day is offered and carried', () async {
    final s = fresh();
    await s.add('2026-11-23', 'Old one');
    await s.add('2026-11-23', 'Finished');
    await s.toggleDone(s.tasks.last.id);
    expect(s.unansweredDay, '2026-11-23');
    await s.carryToToday('2026-11-23');
    expect(s.unansweredDay, isNull);
    expect(s.tasksFor('2026-11-24').single.from, 'From Mon');
  });

  test('streak counts fully answered days and ignores today in progress', () async {
    final s = fresh();
    for (final d in ['2026-11-20', '2026-11-23']) {
      await s.add(d, 'x');
      await s.toggleDone(s.tasks.last.id);
    }
    await s.add('2026-11-24', 'today, still open');
    expect(s.streak, 2);
  });

  test('json round trip', () async {
    final s = fresh();
    await s.setEnabled(true);
    await s.add('2026-11-24', 'A');
    await s.park('B');
    final copy = fresh()..fromJson(s.toJson());
    expect(copy.enabled, isTrue);
    expect(copy.morningMin, 630);
    expect(copy.eveningMin, 1110);
    expect(copy.tasks.single.text, 'A');
    expect(copy.parked.single.text, 'B');
  });

  test('full-day leave moves open tasks to the next work day, skipping other leave days', () async {
    final s = fresh(); // Tue 24 Nov
    await s.setLeave('2026-11-25', LeaveType.leave); // Wed off in advance
    await s.add('2026-11-24', 'Report');
    await s.add('2026-11-24', 'Done one');
    await s.toggleDone(s.tasks.last.id);
    final moved = await s.setLeave('2026-11-24', LeaveType.leave, note: 'Sick');
    expect(moved, 1);
    expect(s.tasksFor('2026-11-26').single.text, 'Report'); // Thu, skipping Wed leave
    expect(s.leaveOn('2026-11-24')!.note, 'Sick');
    expect(s.isOff('2026-11-24'), isTrue);
  });

  test('half-day leave keeps tasks', () async {
    final s = fresh();
    await s.add('2026-11-24', 'A');
    expect(await s.setLeave('2026-11-24', LeaveType.half), 0);
    expect(s.isOff('2026-11-24'), isFalse);
  });

  test('attendance counts working days, leave and holidays', () async {
    final s = fresh(); // Mon 23 .. Tue 24 Nov, plus Fri 20
    await s.setLeave('2026-11-20', LeaveType.holiday);
    await s.setLeave('2026-11-23', LeaveType.half);
    await s.add('2026-11-24', 'x');
    await s.toggleDone(s.tasks.last.id);
    final a = SprintStats(s).attendance(DateTime(2026, 11, 16), DateTime(2026, 11, 24));
    // Counting starts at the first recorded day (Fri 20, a holiday): Mon 23 half (0.5) + Tue 24 (1) = 1.5
    expect(a.workingDays, 1.5);
    expect(a.leaveDays, 0.5);
    expect(a.holidays, 1);
    expect(a.reportedDays, 1);
  });

  test('goal notes update progress; 100% completes the goal', () async {
    final s = fresh();
    final g = await s.addGoal('Get certified', targetDate: '2027-03-31');
    await s.addGoalNote(g.id, 'Module 1 done', progress: 30);
    expect(s.goalById(g.id)!.progress, 30);
    await s.addGoalNote(g.id, 'Passed exam', progress: 100);
    expect(s.goalById(g.id)!.status, GoalStatus.done);
    expect(s.goalById(g.id)!.notes.first.text, 'Passed exam');
  });

  test('review summary lists achievements by category with goals', () async {
    final s = fresh();
    final g = await s.addGoal('Get certified');
    await s.addAchievement('Shipped login revamp', details: 'Errors down 40%', date: '2026-11-10', category: 'delivery', goalId: g.id);
    await s.addAchievement('Mentored 2 juniors', date: '2026-10-02', category: 'teamwork');
    await s.addAchievement('Old one', date: '2025-01-01');
    final text = buildReviewSummary(s, from: '2026-01-01', to: '2026-11-24', periodLabel: '2026');
    expect(text, contains('My achievements – 2026 (2)'));
    expect(text, contains('Delivery\n• 10 Nov – Shipped login revamp  [Goal: Get certified]'));
    expect(text, contains('Errors down 40%'));
    expect(text, contains('Teamwork'));
    expect(text, isNot(contains('Old one')));
    expect(text, contains('Goals\n• Get certified – 0%'));
  });

  test('goals, achievements and leaves survive a json round trip', () async {
    final s = fresh();
    final g = await s.addGoal('G');
    await s.addGoalNote(g.id, 'n', progress: 10);
    await s.addAchievement('A');
    await s.setLeave('2026-11-27', LeaveType.holiday, note: 'Festival');
    final copy = fresh()..fromJson(s.toJson());
    expect(copy.goals.single.notes.single.progress, 10);
    expect(copy.achievements.single.title, 'A');
    expect(copy.leaveOn('2026-11-27')!.note, 'Festival');
  });

  test('attendance starts from the first day Daily Sprint was used', () async {
    final s = fresh(); // Tue 24 Nov
    await s.setEnabled(true); // started today
    final a = SprintStats(s).attendance(DateTime(2026), DateTime(2026, 11, 24));
    expect(a.workingDays, 1);
  });

  test('partly done keeps a note and continues on the next work day with that note', () async {
    final s = fresh();
    await s.add('2026-11-24', 'Write release notes');
    final id = s.tasks.single.id;
    await s.review('2026-11-24', {id: const ReviewAnswer(TaskStatus.partial, note: '  Android part done; iOS left ')});
    final t = s.byId(id)!;
    expect(t.status, TaskStatus.partial);
    expect(t.note, 'Android part done; iOS left');
    final copy = s.tasksFor('2026-11-25').single;
    expect(copy.from, 'Continued from Tue');
    expect(copy.note, 'Android part done; iOS left');
    expect(copy.status, TaskStatus.open);
  });

  test('marking a partly done task done removes the untouched continuation', () async {
    final s = fresh();
    await s.add('2026-11-24', 'A');
    final id = s.tasks.single.id;
    await s.markPartial(id, note: 'half', move: true);
    expect(s.tasks.length, 2);
    await s.toggleDone(id);
    expect(s.byId(id)!.status, TaskStatus.done);
    expect(s.tasks.length, 1);
    expect(s.byId(id)!.note, 'half'); // the note stays
  });

  test('notes: set, clear, keep when the review sends none, survive json', () async {
    final s = fresh();
    await s.add('2026-11-24', 'A');
    final id = s.tasks.single.id;
    await s.setNote(id, 'Waiting for Ravi');
    await s.review('2026-11-24', {id: const ReviewAnswer(TaskStatus.done)});
    expect(s.byId(id)!.note, 'Waiting for Ravi');
    final copy = fresh()..fromJson(s.toJson());
    expect(copy.byId(id)!.note, 'Waiting for Ravi');
    await s.setNote(id, '   ');
    expect(s.byId(id)!.note, isNull);
  });

  test('a partly done task counts as half in completion', () async {
    final s = fresh();
    await s.add('2026-11-24', 'A');
    await s.add('2026-11-24', 'B');
    final ids = s.tasks.map((t) => t.id).toList();
    await s.review('2026-11-24', {ids[0]: const ReviewAnswer(TaskStatus.done), ids[1]: const ReviewAnswer(TaskStatus.partial, move: false)});
    final c = SprintStats(s).countsFor(DateTime(2026, 11, 24));
    expect(c.partial, 1);
    expect(c.rate, 0.75);
  });
}

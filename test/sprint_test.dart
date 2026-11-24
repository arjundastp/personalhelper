import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:remindly/sprint/sprint_state.dart';

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
}

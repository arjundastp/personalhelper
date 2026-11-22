import 'package:flutter_test/flutter_test.dart';
import 'package:remindly/format.dart';
import 'package:remindly/models.dart';

void main() {
  test('weekday summaries', () {
    expect(weekdaysSummary([1, 2, 3, 4, 5]), 'Weekdays');
    expect(weekdaysSummary([6, 7]), 'Weekends');
    expect(weekdaysSummary([5, 1, 3]), 'Mon, Wed, Fri');
    expect(weekdaysSummary([1, 2, 3, 4, 5, 6, 7]), 'Every day');
  });

  test('intervals and ordinals', () {
    expect(fmtInterval(30), '30 min');
    expect(fmtInterval(120), '2 hours');
    expect(fmtInterval(90), '1 h 30 min');
    expect(ordinal(1), '1st');
    expect(ordinal(12), '12th');
    expect(ordinal(23), '23rd');
  });

  test('reminder json round trip', () {
    final r = Reminder(
      id: 3,
      title: 'Pills',
      startDate: DateTime(2026, 11, 22),
      hour: 8,
      minute: 30,
      repeat: RepeatRule(type: 'weekly', weekdays: const [1, 3], endDate: DateTime(2027, 1, 1)),
      soundUri: 'remindly-tune://soft_bells',
    );
    final back = Reminder.fromJson(r.toJson());
    expect(back.title, 'Pills');
    expect(back.repeat.weekdays, [1, 3]);
    expect(back.repeat.endDate, DateTime(2027, 1, 1));
    expect(back.startDateTime, DateTime(2026, 11, 22, 8, 30));
  });

  test('templates use known categories', () {
    for (final t in templates) {
      expect(categories.any((c) => c.key == t.category), isTrue, reason: t.label);
    }
  });
}

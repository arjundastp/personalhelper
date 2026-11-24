import '../models.dart' show isoDate, dateOnly;
import 'sprint_state.dart';

/// How one day's tasks ended.
class DayCounts {
  final DateTime day;
  final int done, notDone, paused, open;
  const DayCounts(this.day, {this.done = 0, this.notDone = 0, this.paused = 0, this.open = 0});

  int get total => done + notDone + paused + open;

  /// Share done, or null when nothing was planned.
  double? get rate => total == 0 ? null : done / total;
}

class SlippingTask {
  final String text;
  final int timesNotDone;
  final bool stillOpen;
  const SlippingTask(this.text, this.timesNotDone, this.stillOpen);
}

/// Numbers for the Insights dashboard, computed from [SprintState] for a window of [days]
/// ending today (today included).
class SprintStats {
  final SprintState s;
  final int days;
  final DateTime today;

  SprintStats(this.s, {this.days = 7, DateTime? now}) : today = dateOnly(now ?? s.now());

  DayCounts countsFor(DateTime day) {
    var done = 0, not = 0, paused = 0, open = 0;
    for (final t in s.tasksFor(isoDate(day))) {
      switch (t.status) {
        case TaskStatus.done:
          done++;
        case TaskStatus.notDone:
          not++;
        case TaskStatus.paused:
          paused++;
        default:
          open++;
      }
    }
    return DayCounts(day, done: done, notDone: not, paused: paused, open: open);
  }

  /// One entry per calendar day in the window, oldest first.
  List<DayCounts> get daily => [
        for (var i = days - 1; i >= 0; i--) countsFor(today.subtract(Duration(days: i))),
      ];

  DayCounts _sum(Iterable<DayCounts> list, DateTime day) {
    var d = 0, n = 0, p = 0, o = 0;
    for (final c in list) {
      d += c.done;
      n += c.notDone;
      p += c.paused;
      o += c.open;
    }
    return DayCounts(day, done: d, notDone: n, paused: p, open: o);
  }

  DayCounts get totals => _sum(daily, today);

  /// The window just before this one, for "vs previous" deltas.
  DayCounts get previousTotals => _sum(
        [for (var i = 2 * days - 1; i >= days; i--) countsFor(today.subtract(Duration(days: i)))],
        today.subtract(Duration(days: days)),
      );

  /// Completion rate in percent (0-100), or null if nothing was planned.
  int? get completion => totals.rate == null ? null : (totals.rate! * 100).round();

  /// Change in completion rate vs the previous window, in percentage points.
  int? get completionDelta {
    final now = totals.rate, before = previousTotals.rate;
    if (now == null || before == null) return null;
    return ((now - before) * 100).round();
  }

  int get plannedDays => daily.where((d) => d.total > 0).length;

  /// Completion by weekday (1 = Mon .. 7 = Sun) over the last 8 weeks; null where nothing planned.
  Map<int, double?> get weekdayRates {
    final done = List.filled(8, 0), total = List.filled(8, 0);
    for (var i = 0; i < 56; i++) {
      final c = countsFor(today.subtract(Duration(days: i)));
      done[c.day.weekday] += c.done;
      total[c.day.weekday] += c.total;
    }
    return {for (var w = 1; w <= 7; w++) w: total[w] == 0 ? null : done[w] / total[w]};
  }

  /// Calendar heatmap: [weeks] full weeks (Mon..Sun rows), the last one containing today.
  /// Days after today are null.
  List<List<DayCounts?>> heatmap({int weeks = 5}) {
    final monday = today.subtract(Duration(days: today.weekday - 1));
    final start = monday.subtract(Duration(days: 7 * (weeks - 1)));
    return [
      for (var w = 0; w < weeks; w++)
        [
          for (var d = 0; d < 7; d++)
            () {
              final day = start.add(Duration(days: 7 * w + d));
              return day.isAfter(today) ? null : countsFor(day);
            }(),
        ],
    ];
  }

  /// Tasks marked "Not done" on two or more days in the last 30 days: candidates to split or park.
  List<SlippingTask> get slipping {
    final cutoff = isoDate(today.subtract(const Duration(days: 30)));
    final notDone = <String, int>{};
    final label = <String, String>{};
    for (final t in s.tasks) {
      if (t.date.compareTo(cutoff) < 0) continue;
      final key = t.text.trim().toLowerCase();
      label[key] = t.text.trim();
      if (t.status == TaskStatus.notDone) notDone[key] = (notDone[key] ?? 0) + 1;
    }
    final openKeys = {
      for (final t in s.tasks)
        if (t.status == TaskStatus.open) t.text.trim().toLowerCase(),
    };
    final list = [
      for (final e in notDone.entries)
        if (e.value >= 2) SlippingTask(label[e.key]!, e.value, openKeys.contains(e.key)),
    ]..sort((a, b) => b.timesNotDone.compareTo(a.timesNotDone));
    return list.take(3).toList();
  }
}

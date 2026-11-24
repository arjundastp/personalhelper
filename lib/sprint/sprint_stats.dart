import '../models.dart' show isoDate, dateOnly;
import 'sprint_state.dart';

/// How one day's tasks ended.
class DayCounts {
  final DateTime day;
  final int done, partial, notDone, paused, open;
  const DayCounts(this.day, {this.done = 0, this.partial = 0, this.notDone = 0, this.paused = 0, this.open = 0});

  int get total => done + partial + notDone + paused + open;

  /// Share done (a partly done task counts as half), or null when nothing was planned.
  double? get rate => total == 0 ? null : (done + partial * 0.5) / total;
}

/// Working days and time off in a date range (only days up to today count).
class Attendance {
  final double workingDays; // work days actually worked (half-day leave counts 0.5)
  final double leaveDays; // full leave = 1, half day = 0.5
  final int fullLeaves, halfDays, holidays;
  final int reportedDays; // worked days with a plan where every task got an answer
  final int plannedDays; // worked days that had a plan
  const Attendance({
    this.workingDays = 0,
    this.leaveDays = 0,
    this.fullLeaves = 0,
    this.halfDays = 0,
    this.holidays = 0,
    this.reportedDays = 0,
    this.plannedDays = 0,
  });
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
    var done = 0, partial = 0, not = 0, paused = 0, open = 0;
    for (final t in s.tasksFor(isoDate(day))) {
      switch (t.status) {
        case TaskStatus.done:
          done++;
        case TaskStatus.partial:
          partial++;
        case TaskStatus.notDone:
          not++;
        case TaskStatus.paused:
          paused++;
        default:
          open++;
      }
    }
    return DayCounts(day, done: done, partial: partial, notDone: not, paused: paused, open: open);
  }

  /// One entry per calendar day in the window, oldest first.
  List<DayCounts> get daily => [
        for (var i = days - 1; i >= 0; i--) countsFor(today.subtract(Duration(days: i))),
      ];

  DayCounts _sum(Iterable<DayCounts> list, DateTime day) {
    var d = 0, h = 0, n = 0, p = 0, o = 0;
    for (final c in list) {
      d += c.done;
      h += c.partial;
      n += c.notDone;
      p += c.paused;
      o += c.open;
    }
    return DayCounts(day, done: d, partial: h, notDone: n, paused: p, open: o);
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
    final done = List.filled(8, 0.0), total = List.filled(8, 0);
    for (var i = 0; i < 56; i++) {
      final c = countsFor(today.subtract(Duration(days: i)));
      done[c.day.weekday] += c.done + c.partial * 0.5;
      total[c.day.weekday] += c.total;
    }
    return {for (var w = 1; w <= 7; w++) w: total[w] == 0 ? null : done[w] / total[w]};
  }

  /// The weekday with the highest completion over the last 8 weeks, counting only weekdays with at
  /// least [minTasks] tasks. Null when there is not enough history yet.
  ({int weekday, double rate, int tasks})? bestWeekday({int minTasks = 4}) {
    final done = List.filled(8, 0.0), total = List.filled(8, 0);
    for (var i = 0; i < 56; i++) {
      final c = countsFor(today.subtract(Duration(days: i)));
      done[c.day.weekday] += c.done + c.partial * 0.5;
      total[c.day.weekday] += c.total;
    }
    ({int weekday, double rate, int tasks})? best;
    for (var w = 1; w <= 7; w++) {
      if (total[w] < minTasks) continue;
      final r = done[w] / total[w];
      if (best == null || r > best.rate || (r == best.rate && total[w] > best.tasks)) best = (weekday: w, rate: r, tasks: total[w]);
    }
    return best;
  }

  /// The single best day in the last [days] days (highest completion, then most tasks done),
  /// counting days with at least 2 tasks. Today counts only once every task has an answer.
  DayCounts? bestDay({int days = 30}) {
    DayCounts? best;
    for (var i = 0; i < days; i++) {
      final c = countsFor(today.subtract(Duration(days: i)));
      if (c.total < 2 || (i == 0 && c.open > 0)) continue;
      final r = c.rate!;
      if (best == null || r > best.rate! || (r == best.rate! && c.done > best.done)) best = c;
    }
    return best;
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

  /// Attendance between [from] and [to] (inclusive), capped at today.
  Attendance attendance(DateTime from, DateTime to) {
    final end = to.isAfter(today) ? today : dateOnly(to);
    final first = DateTime.parse(s.firstDay);
    if (from.isBefore(first)) from = first;
    var working = 0.0, leave = 0.0;
    var full = 0, half = 0, holidays = 0, reported = 0, planned = 0;
    for (var d = dateOnly(from); !d.isAfter(end); d = d.add(const Duration(days: 1))) {
      final key = isoDate(d);
      final off = s.leaveOn(key);
      final workday = s.workdays.contains(d.weekday);
      if (off != null) {
        switch (off.type) {
          case LeaveType.holiday:
            holidays++;
          case LeaveType.half:
            half++;
            leave += 0.5;
            if (workday) working += 0.5;
          default:
            full++;
            leave += 1;
        }
      } else if (workday) {
        working += 1;
      }
      final list = s.tasksFor(key);
      if (list.isNotEmpty && (off == null || !off.fullDayOff)) {
        planned++;
        if (list.every((t) => t.status != TaskStatus.open)) reported++;
      }
    }
    return Attendance(
      workingDays: working,
      leaveDays: leave,
      fullLeaves: full,
      halfDays: half,
      holidays: holidays,
      reportedDays: reported,
      plannedDays: planned,
    );
  }

  Attendance get windowAttendance => attendance(today.subtract(Duration(days: days - 1)), today);
  Attendance get monthAttendance => attendance(DateTime(today.year, today.month), today);
  Attendance get yearAttendance => attendance(DateTime(today.year), today);

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

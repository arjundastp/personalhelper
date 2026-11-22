import 'package:intl/intl.dart';
import 'package:material_ui/material_ui.dart';

import 'models.dart';

const weekdayShort = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
const weekdayLetter = ['M', 'T', 'W', 'T', 'F', 'S', 'S'];

String fmtTime(BuildContext context, DateTime t) {
  final use24 = MediaQuery.of(context).alwaysUse24HourFormat;
  return use24 ? DateFormat.Hm().format(t) : DateFormat.jm().format(t);
}

String fmtMinutesOfDay(BuildContext context, int m) =>
    fmtTime(context, DateTime(2000, 1, 1, m ~/ 60, m % 60));

String fmtDay(DateTime d, {bool withYear = false}) {
  final today = dateOnly(DateTime.now());
  final diff = dateOnly(d).difference(today).inDays;
  if (diff == 0) return 'Today';
  if (diff == 1) return 'Tomorrow';
  if (diff == -1) return 'Yesterday';
  if (diff > 1 && diff < 7) return DateFormat('EEEE').format(d);
  return DateFormat(withYear || d.year != today.year ? 'EEE, d MMM y' : 'EEE, d MMM').format(d);
}

String fmtWhen(BuildContext context, DateTime t) => '${fmtDay(t)}, ${fmtTime(context, t)}';

String fmtRelative(DateTime t) {
  final d = t.difference(DateTime.now());
  if (d.isNegative) return 'now';
  final mins = (d.inSeconds / 60).ceil();
  if (mins < 1) return 'in less than a minute';
  if (mins < 60) return 'in $mins min';
  final h = mins ~/ 60, m = mins % 60;
  if (h < 24) return m == 0 ? 'in $h h' : 'in $h h $m min';
  final days = (d.inHours / 24).round();
  if (days < 45) return 'in $days day${days == 1 ? '' : 's'}';
  final months = (days / 30).round();
  return 'in about $months month${months == 1 ? '' : 's'}';
}

String ordinal(int n) {
  if (n >= 11 && n <= 13) return '${n}th';
  return switch (n % 10) { 1 => '${n}st', 2 => '${n}nd', 3 => '${n}rd', _ => '${n}th' };
}

String fmtInterval(int minutes) {
  if (minutes < 60) return '$minutes min';
  final h = minutes ~/ 60, m = minutes % 60;
  final hs = h == 1 ? '1 hour' : '$h hours';
  return m == 0 ? hs : '$h h $m min';
}

String weekdaysSummary(List<int> days) {
  final s = days.toSet();
  if (s.length == 7) return 'Every day';
  if (s.length == 5 && s.containsAll([1, 2, 3, 4, 5])) return 'Weekdays';
  if (s.length == 2 && s.containsAll([6, 7])) return 'Weekends';
  final sorted = s.toList()..sort();
  return sorted.map((d) => weekdayShort[d - 1]).join(', ');
}

/// Human-friendly description of how a reminder repeats, e.g. "Every 2 hours · 8:00 AM – 10:00 PM".
String repeatSummary(BuildContext context, Reminder r) {
  final rule = r.repeat;
  final n = rule.interval;
  String text;
  switch (rule.type) {
    case 'daily':
      text = n == 1 ? 'Every day' : 'Every $n days';
    case 'weekly':
      final days = rule.weekdays.isEmpty ? [r.startDate.weekday] : rule.weekdays;
      final base = weekdaysSummary(days);
      text = n == 1 ? (days.length == 1 ? 'Every ${weekdayShort[days.first - 1]}' : base) : 'Every $n weeks · $base';
    case 'monthly':
      final day = ordinal(r.startDate.day);
      text = n == 1 ? 'Monthly on the $day' : 'Every $n months on the $day';
    case 'yearly':
      final d = DateFormat('d MMM').format(r.startDate);
      text = n == 1 ? 'Every year on $d' : 'Every $n years on $d';
    case 'hourly':
      final end = rule.windowEnd ?? 23 * 60 + 59;
      text = 'Every ${fmtInterval(n)} · ${fmtMinutesOfDay(context, r.hour * 60 + r.minute)} – ${fmtMinutesOfDay(context, end)}';
    default:
      return 'Once · ${fmtDay(r.startDate)}';
  }
  if (rule.endDate != null) text += ' · until ${DateFormat('d MMM y').format(rule.endDate!)}';
  return text;
}

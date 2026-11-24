import 'package:intl/intl.dart';

import 'sprint_state.dart';

class AchievementCategory {
  final String key;
  final String label;
  const AchievementCategory(this.key, this.label);
}

const achievementCategories = [
  AchievementCategory('delivery', 'Delivery'),
  AchievementCategory('quality', 'Quality'),
  AchievementCategory('teamwork', 'Teamwork'),
  AchievementCategory('learning', 'Learning'),
  AchievementCategory('recognition', 'Recognition'),
  AchievementCategory('other', 'Other'),
];

String categoryLabel(String key) => achievementCategories.firstWhere((c) => c.key == key, orElse: () => achievementCategories.last).label;

/// Plain-text summary for a review meeting: achievements grouped by category, then goals.
/// Built only on the phone; it leaves the phone only if the user taps Share.
String buildReviewSummary(SprintState s, {required String from, required String to, required String periodLabel}) {
  final list = s.achievementsBetween(from, to);
  final fmt = DateFormat('d MMM');
  final b = StringBuffer('My achievements – $periodLabel (${list.length})\n');
  for (final c in achievementCategories) {
    final items = list.where((a) => a.category == c.key).toList();
    if (items.isEmpty) continue;
    b.write('\n${c.label}\n');
    for (final a in items) {
      b.write('• ${fmt.format(DateTime.parse(a.date))} – ${a.title}');
      final goal = s.goalById(a.goalId);
      if (goal != null) b.write('  [Goal: ${goal.title}]');
      b.write('\n');
      if (a.details.isNotEmpty) b.write('  ${a.details.replaceAll('\n', '\n  ')}\n');
    }
  }
  final goals = s.goals.where((g) => g.status != GoalStatus.dropped).toList();
  if (goals.isNotEmpty) {
    b.write('\nGoals\n');
    for (final g in goals) {
      b.write('• ${g.title} – ${g.status == GoalStatus.done ? 'completed' : '${g.progress}%'}');
      if (g.targetDate != null && g.status != GoalStatus.done) {
        b.write(' (target ${DateFormat('MMM y').format(DateTime.parse(g.targetDate!))})');
      }
      b.write('\n');
      if (g.notes.isNotEmpty && g.notes.first.text.isNotEmpty) {
        b.write('  Latest: ${fmt.format(DateTime.parse(g.notes.first.date))} – ${g.notes.first.text}\n');
      }
    }
  }
  return b.toString().trimRight();
}

import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:material_ui/material_ui.dart';

import '../main.dart' show AppColors;
import '../models.dart' show isoDate, dateOnly;
import '../native.dart';
import '../widgets.dart';
import 'goals_view.dart' show BottomAddBar;
import 'insights_view.dart' show SprintColors;
import 'review_export.dart';
import 'sprint_state.dart';

IconData categoryIcon(String key) => switch (key) {
      'delivery' => Icons.rocket_launch_outlined,
      'quality' => Icons.verified_outlined,
      'teamwork' => Icons.groups_outlined,
      'learning' => Icons.school_outlined,
      'recognition' => Icons.emoji_events_outlined,
      _ => Icons.star_outline_rounded,
    };

/// Review periods for the filter: (label, from date). The end is always today.
List<(String, DateTime?)> _periods(DateTime now) {
  final q = (now.month - 1) ~/ 3;
  final qStart = DateTime(now.year, q * 3 + 1);
  final half = now.month <= 6 ? DateTime(now.year) : DateTime(now.year, 7);
  return [
    ('This quarter', qStart),
    (now.month <= 6 ? 'Jan–Jun' : 'Jul–Dec', half),
    ('This year', DateTime(now.year)),
    ('All', null),
  ];
}

/// The "Achievements" tab: wins to show in review meetings, with a one-tap summary to share.
class AchievementsView extends StatefulWidget {
  const AchievementsView({super.key});

  @override
  State<AchievementsView> createState() => _AchievementsViewState();
}

class _AchievementsViewState extends State<AchievementsView> with AutomaticKeepAliveClientMixin {
  final s = SprintState.instance;
  int period = 2; // This year

  @override
  bool get wantKeepAlive => true;

  Future<void> _share(String label, String from) async {
    final text = buildReviewSummary(s, from: from, to: s.today, periodLabel: label);
    final choice = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      builder: (c) => SafeArea(
        child: ConstrainedBox(
          constraints: BoxConstraints(maxHeight: MediaQuery.of(c).size.height * 0.85),
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Padding(
              padding: EdgeInsets.fromLTRB(20, 0, 20, 6),
              child: Text('Review summary', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w600)),
            ),
            Flexible(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(20, 4, 20, 8),
                child: SelectableText(text, style: const TextStyle(fontSize: 13.5, height: 1.45)),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 6, 16, 12),
              child: Row(children: [
                Expanded(
                  child: OutlinedButton.icon(
                    style: OutlinedButton.styleFrom(minimumSize: const Size(0, 42)),
                    onPressed: () => Navigator.pop(c, 'copy'),
                    icon: const Icon(Icons.copy_rounded, size: 18),
                    label: const Text('Copy'),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: FilledButton.icon(
                    style: FilledButton.styleFrom(minimumSize: const Size(0, 42)),
                    onPressed: () => Navigator.pop(c, 'share'),
                    icon: const Icon(Icons.share_outlined, size: 18),
                    label: const Text('Share'),
                  ),
                ),
              ]),
            ),
          ]),
        ),
      ),
    );
    if (!mounted) return;
    if (choice == 'copy') {
      await Clipboard.setData(ClipboardData(text: text));
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Copied. Paste it into your review notes.')));
    } else if (choice == 'share') {
      await Native.shareText(text);
    }
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    return ListenableBuilder(
      listenable: s,
      builder: (context, _) {
        final c = SprintColors.of(context);
        final periods = _periods(dateOnly(DateTime.now()));
        final (label, from) = periods[period];
        final fromKey = from == null ? '0000-01-01' : isoDate(from);
        final list = s.achievementsBetween(fromKey, '9999-12-31');
        final byMonth = <String, List<Achievement>>{};
        for (final a in list) {
          byMonth.putIfAbsent(DateFormat('MMMM y').format(DateTime.parse(a.date)), () => []).add(a);
        }
        final counts = <String, int>{};
        for (final a in list) {
          counts[a.category] = (counts[a.category] ?? 0) + 1;
        }
        return Column(children: [
          // ---- period filter + share ----
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 8, 6, 0),
            child: Row(children: [
              Expanded(
                child: SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(children: [
                    for (var i = 0; i < periods.length; i++)
                      Padding(
                        padding: const EdgeInsets.only(right: 6),
                        child: ChoiceChip(
                          visualDensity: VisualDensity.compact,
                          padding: const EdgeInsets.symmetric(horizontal: 2),
                          labelStyle: TextStyle(fontSize: 12.5, color: c.ink),
                          showCheckmark: false,
                          label: Text(periods[i].$1),
                          selected: period == i,
                          onSelected: (_) => setState(() => period = i),
                        ),
                      ),
                  ]),
                ),
              ),
              IconButton(
                tooltip: 'Share for review',
                onPressed: list.isEmpty ? null : () => _share(label, fromKey),
                icon: const Icon(Icons.ios_share_rounded),
              ),
            ]),
          ),
          Expanded(
            child: list.isEmpty
                ? Center(
                    child: Padding(
                      padding: const EdgeInsets.all(32),
                      child: Column(mainAxisSize: MainAxisSize.min, children: [
                        Icon(Icons.emoji_events_outlined, size: 48, color: c.muted.withValues(alpha: 0.5)),
                        const SizedBox(height: 10),
                        Text(
                          s.achievements.isEmpty
                              ? 'Note your wins as they happen.\nAt review time, share them in one tap.'
                              : 'Nothing in this period.',
                          textAlign: TextAlign.center,
                          style: TextStyle(fontSize: 14.5, color: c.muted, height: 1.4),
                        ),
                      ]),
                    ),
                  )
                : ListView(
                    padding: const EdgeInsets.only(bottom: 12),
                    children: [
                      // summary chips by category
                      Padding(
                        padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
                        child: Wrap(spacing: 12, runSpacing: 4, children: [
                          Text('${list.length} total',
                              style: TextStyle(fontSize: 12.5, color: c.ink, fontWeight: FontWeight.w600)),
                          for (final cat in achievementCategories)
                            if ((counts[cat.key] ?? 0) > 0)
                              Text('${cat.label} ${counts[cat.key]}', style: TextStyle(fontSize: 12.5, color: c.muted)),
                        ]),
                      ),
                      for (final e in byMonth.entries) ...[
                        ListHeader(e.key),
                        for (final a in e.value) _AchievementRow(a: a),
                      ],
                    ],
                  ),
          ),
          BottomAddBar(label: 'Add an achievement', icon: Icons.emoji_events_outlined, onTap: () => showAchievementSheet(context)),
        ]);
      },
    );
  }
}

class _AchievementRow extends StatelessWidget {
  final Achievement a;
  const _AchievementRow({required this.a});

  @override
  Widget build(BuildContext context) {
    final c = SprintColors.of(context);
    final goal = SprintState.instance.goalById(a.goalId);
    return InkWell(
      onTap: () => showAchievementSheet(context, existing: a),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Container(
            width: 34,
            height: 34,
            decoration: BoxDecoration(color: c.done.withValues(alpha: 0.13), shape: BoxShape.circle),
            child: Icon(categoryIcon(a.category), size: 18, color: c.ink),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(a.title, style: TextStyle(fontSize: 15, color: c.ink, fontWeight: FontWeight.w500)),
              if (a.details.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: 1),
                  child: Text(a.details, maxLines: 2, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 13, color: c.muted, height: 1.3)),
                ),
              Padding(
                padding: const EdgeInsets.only(top: 2),
                child: Text(
                  [DateFormat('d MMM').format(DateTime.parse(a.date)), categoryLabel(a.category), if (goal != null) 'Goal: ${goal.title}'].join(' · '),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: 12, color: c.muted),
                ),
              ),
            ]),
          ),
        ]),
      ),
    );
  }
}

/// Add or edit an achievement. [title] pre-fills it (e.g. from a finished task).
Future<void> showAchievementSheet(BuildContext context, {Achievement? existing, String? title, String? date}) async {
  final s = SprintState.instance;
  final titleCtrl = TextEditingController(text: existing?.title ?? title ?? '');
  final details = TextEditingController(text: existing?.details ?? '');
  var category = existing?.category ?? 'delivery';
  var when = existing?.date ?? date ?? s.today;
  int? goalId = existing?.goalId;
  final activeGoals = s.goals.where((g) => g.status != GoalStatus.dropped).toList();
  final result = await showModalBottomSheet<String>(
    context: context,
    isScrollControlled: true,
    builder: (c) => StatefulBuilder(
      builder: (c, set) => Padding(
        padding: EdgeInsets.only(bottom: MediaQuery.of(c).viewInsets.bottom),
        child: SafeArea(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
            child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                Expanded(
                  child: Text(existing == null ? 'New achievement' : 'Achievement',
                      style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w600)),
                ),
                if (existing != null)
                  IconButton(
                    tooltip: 'Delete',
                    onPressed: () => Navigator.pop(c, 'delete'),
                    icon: const Icon(Icons.delete_outline_rounded, color: AppColors.red),
                  ),
              ]),
              TextField(
                controller: titleCtrl,
                autofocus: existing == null && title == null,
                textCapitalization: TextCapitalization.sentences,
                style: const TextStyle(fontSize: 15.5),
                decoration: const InputDecoration(labelText: 'What did you achieve?', hintText: 'e.g. Shipped the new login flow'),
              ),
              TextField(
                controller: details,
                minLines: 1,
                maxLines: 4,
                textCapitalization: TextCapitalization.sentences,
                style: const TextStyle(fontSize: 14.5),
                decoration: const InputDecoration(labelText: 'Impact / details (optional)', hintText: 'e.g. Cut sign-in errors by 40%'),
              ),
              const SizedBox(height: 12),
              Wrap(spacing: 6, runSpacing: 6, children: [
                for (final cat in achievementCategories)
                  ChoiceChip(
                    visualDensity: VisualDensity.compact,
                    avatar: Icon(categoryIcon(cat.key), size: 16),
                    showCheckmark: false,
                    label: Text(cat.label, style: const TextStyle(fontSize: 13)),
                    selected: category == cat.key,
                    onSelected: (_) => set(() => category = cat.key),
                  ),
              ]),
              const SizedBox(height: 4),
              OptionRow(
                icon: Icons.event_outlined,
                title: 'Date',
                value: DateFormat('EEE, d MMM y').format(DateTime.parse(when)),
                onTap: () async {
                  final now = DateTime.now();
                  final d = await showDatePicker(
                    context: c,
                    initialDate: DateTime.parse(when),
                    firstDate: DateTime(now.year - 5),
                    lastDate: now,
                  );
                  if (d != null) set(() => when = isoDate(d));
                },
              ),
              if (activeGoals.isNotEmpty)
                OptionRow(
                  icon: Icons.flag_outlined,
                  title: 'Linked goal',
                  value: s.goalById(goalId)?.title ?? 'None',
                  onTap: () async {
                    final v = await chooseOne<int>(
                      c,
                      title: 'Link to a goal',
                      options: [(-1, 'None'), for (final g in activeGoals) (g.id, g.title)],
                      current: goalId ?? -1,
                    );
                    if (v != null) set(() => goalId = v < 0 ? null : v);
                  },
                ),
              const SizedBox(height: 6),
              SizedBox(
                width: double.infinity,
                child: FilledButton(onPressed: () => Navigator.pop(c, 'save'), child: const Text('Save')),
              ),
            ]),
          ),
        ),
      ),
    ),
  );
  if (result == 'delete' && existing != null) {
    await s.deleteAchievement(existing.id);
  } else if (result == 'save' && titleCtrl.text.trim().isNotEmpty) {
    if (existing == null) {
      await s.addAchievement(titleCtrl.text, details: details.text, date: when, category: category, goalId: goalId);
    } else {
      await s.update((_) {
        existing.title = titleCtrl.text.trim();
        existing.details = details.text.trim();
        existing.date = when;
        existing.category = category;
        existing.goalId = goalId;
      });
    }
  }
}

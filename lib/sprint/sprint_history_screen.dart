import 'package:intl/intl.dart';
import 'package:material_ui/material_ui.dart';

import '../format.dart' show fmtDay;
import '../main.dart' show AppColors;
import '../models.dart' show dateOnly;
import '../widgets.dart';
import 'review_screen.dart';
import 'sprint_screen.dart' show sprintBlue, notDoneColor;
import 'sprint_state.dart';

/// Past days, laid out like a call log: one row per planned day with its score.
class SprintHistoryScreen extends StatelessWidget {
  const SprintHistoryScreen({super.key});

  String _group(String day) {
    final d = DateTime.parse(day);
    final now = dateOnly(DateTime.now());
    final monday = now.subtract(Duration(days: now.weekday - 1));
    if (!d.isBefore(monday)) return 'This week';
    if (!d.isBefore(monday.subtract(const Duration(days: 7)))) return 'Last week';
    return DateFormat('MMMM y').format(d);
  }

  @override
  Widget build(BuildContext context) {
    final sprint = SprintState.instance;
    final theme = Theme.of(context);
    final grey = theme.colorScheme.onSurfaceVariant;
    final light = theme.brightness == Brightness.light;
    return ListenableBuilder(
      listenable: sprint,
      builder: (context, _) {
        final days = sprint.pastDays;
        final week = sprint.weekStats();
        final groups = <String, List<String>>{};
        for (final d in days) {
          groups.putIfAbsent(_group(d), () => []).add(d);
        }
        Widget stat(String value, String label, {Color? color}) => Expanded(
              child: Column(children: [
                Text(value, style: TextStyle(fontSize: 24, fontWeight: FontWeight.w700, color: color)),
                Text(label, textAlign: TextAlign.center, style: TextStyle(fontSize: 13.5, color: grey)),
              ]),
            );
        return Scaffold(
          appBar: AppBar(title: const Text('Past days')),
          body: days.isEmpty
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(32),
                    child: Text('No days yet. Plan some tasks and they will show up here.',
                        textAlign: TextAlign.center, style: TextStyle(fontSize: 16, color: grey)),
                  ),
                )
              : ListView(
                  padding: const EdgeInsets.only(bottom: 24),
                  children: [
                    Container(
                      margin: const EdgeInsets.all(16),
                      padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 8),
                      decoration: BoxDecoration(
                        color: light ? const Color(0xFFF0F2F5) : const Color(0xFF1F2C34),
                        borderRadius: BorderRadius.circular(18),
                      ),
                      child: Row(children: [
                        stat('${week.done}', 'done this week', color: light ? AppColors.green : AppColors.accent),
                        stat('${week.planned}', 'planned'),
                        stat('${sprint.streak}', 'days in a row'),
                      ]),
                    ),
                    for (final g in groups.entries) ...[
                      ListHeader(g.key),
                      for (final d in g.value) _DayRow(day: d),
                    ],
                    Padding(
                      padding: const EdgeInsets.fromLTRB(24, 16, 24, 0),
                      child: Text('Tap a day to see its tasks.', textAlign: TextAlign.center, style: TextStyle(fontSize: 13.5, color: grey)),
                    ),
                  ],
                ),
        );
      },
    );
  }
}

class _DayRow extends StatelessWidget {
  final String day;
  const _DayRow({required this.day});

  @override
  Widget build(BuildContext context) {
    final sprint = SprintState.instance;
    final theme = Theme.of(context);
    final grey = theme.colorScheme.onSurfaceVariant;
    final list = sprint.tasksFor(day);
    final done = list.where((t) => t.status == TaskStatus.done).length;
    final not = list.where((t) => t.status == TaskStatus.notDone).length;
    final moved = list.where((t) => t.status == TaskStatus.notDone && t.movedId != null).length;
    final paused = list.where((t) => t.status == TaskStatus.paused).length;
    final open = list.where((t) => t.status == TaskStatus.open).length;
    final good = list.isNotEmpty && done / list.length >= 0.6;
    final parts = <String>[
      if (done == list.length) 'All done' else '$done done',
      if (moved > 0) '$moved moved',
      if (not - moved > 0) '${not - moved} not done',
      if (paused > 0) '$paused paused',
      if (open > 0) '$open not updated',
    ];
    final d = DateTime.parse(day);
    final rel = fmtDay(d);
    return InkWell(
      onTap: () => _showDay(context, day),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 10, 16, 10),
        child: Row(children: [
          Container(
            width: 54,
            height: 54,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: (good ? AppColors.accent : notDoneColor).withValues(alpha: 0.15),
            ),
            child: Text('$done/${list.length}',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: good ? const Color(0xFF00695C) : notDoneColor)),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                Expanded(
                  child: Text(rel == 'Today' || rel == 'Yesterday' ? rel : DateFormat('EEEE').format(d),
                      style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w600)),
                ),
                Text(DateFormat('d MMM').format(d), style: TextStyle(fontSize: 13.5, color: grey)),
              ]),
              const SizedBox(height: 3),
              Text(parts.join(' · '), maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 14.5, color: grey)),
            ]),
          ),
        ]),
      ),
    );
  }

  void _showDay(BuildContext context, String day) {
    final sprint = SprintState.instance;
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (c) {
        final grey = Theme.of(c).colorScheme.onSurfaceVariant;
        final list = sprint.tasksFor(day);
        return SafeArea(
          child: ConstrainedBox(
            constraints: BoxConstraints(maxHeight: MediaQuery.of(c).size.height * 0.8),
            child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(24, 0, 24, 8),
                child: Text(DateFormat('EEEE, d MMMM').format(DateTime.parse(day)),
                    style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w600)),
              ),
              Flexible(
                child: ListView(shrinkWrap: true, children: [
                  for (final t in list)
                    ListTile(
                      leading: Icon(
                        switch (t.status) {
                          TaskStatus.done => Icons.check_circle_rounded,
                          TaskStatus.notDone => Icons.cancel_rounded,
                          TaskStatus.paused => Icons.pause_circle_rounded,
                          _ => Icons.radio_button_unchecked_rounded,
                        },
                        color: switch (t.status) {
                          TaskStatus.done => AppColors.accent,
                          TaskStatus.notDone => notDoneColor,
                          TaskStatus.paused => sprintBlue,
                          _ => grey,
                        },
                        size: 28,
                      ),
                      title: Text(t.text),
                      subtitle: Text(switch (t.status) {
                        TaskStatus.done => 'Done',
                        TaskStatus.notDone => t.movedId != null ? 'Not done · moved to next day' : 'Not done',
                        TaskStatus.paused => 'Paused',
                        _ => 'Not updated',
                      }),
                    ),
                ]),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 8, 20, 12),
                child: SizedBox(
                  width: double.infinity,
                  child: OutlinedButton(
                    onPressed: () {
                      Navigator.pop(c);
                      Navigator.of(context).push(MaterialPageRoute(builder: (_) => ReviewScreen(date: day)));
                    },
                    child: const Text('Change status'),
                  ),
                ),
              ),
            ]),
          ),
        );
      },
    );
  }
}

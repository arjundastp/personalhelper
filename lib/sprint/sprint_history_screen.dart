import 'package:intl/intl.dart';
import 'package:material_ui/material_ui.dart';

import '../format.dart' show fmtDay;
import '../models.dart' show dateOnly;
import '../widgets.dart';
import 'insights_view.dart' show SprintColors;
import 'review_screen.dart';
import 'sprint_state.dart';

/// The "History" tab: one compact row per planned day, like a call log.
class SprintHistoryView extends StatelessWidget {
  const SprintHistoryView({super.key});

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
    final grey = Theme.of(context).colorScheme.onSurfaceVariant;
    return ListenableBuilder(
      listenable: sprint,
      builder: (context, _) {
        final days = sprint.pastDays;
        if (days.isEmpty) {
          return Center(
            child: Padding(
              padding: const EdgeInsets.all(32),
              child: Text(
                'Days you plan will show up here.',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 14.5, color: grey),
              ),
            ),
          );
        }
        final groups = <String, List<String>>{};
        for (final d in days) {
          groups.putIfAbsent(_group(d), () => []).add(d);
        }
        return ListView(
          padding: const EdgeInsets.only(bottom: 20),
          children: [
            for (final g in groups.entries) ...[ListHeader(g.key), for (final d in g.value) _DayRow(day: d)],
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 12, 24, 0),
              child: Text(
                'Tap a day to see its tasks',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 12, color: grey),
              ),
            ),
          ],
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
    final c = SprintColors.of(context);
    final list = sprint.tasksFor(day);
    final done = list.where((t) => t.status == TaskStatus.done).length;
    final not = list.where((t) => t.status == TaskStatus.notDone).length;
    final paused = list.where((t) => t.status == TaskStatus.paused).length;
    final open = list.where((t) => t.status == TaskStatus.open).length;
    final leave = sprint.leaveOn(day);
    final parts = <String>[
      if (leave != null) leave.note == null ? leave.label : '${leave.label} (${leave.note})',
      if (list.isNotEmpty) done == list.length ? 'All done' : '$done done',
      if (not > 0) '$not not done',
      if (paused > 0) '$paused paused',
      if (open > 0) '$open not updated',
    ];
    final d = DateTime.parse(day);
    final rel = fmtDay(d);
    final rate = list.isEmpty ? 0.0 : done / list.length;
    return InkWell(
      onTap: list.isEmpty ? null : () => _showDay(context, day),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
        child: Row(
          children: [
            // Small ring showing the share done.
            if (list.isEmpty && leave != null)
              Container(
                width: 38,
                height: 38,
                decoration: BoxDecoration(color: c.leave.withValues(alpha: 0.35), shape: BoxShape.circle),
                child: Icon(
                  leave.type == LeaveType.holiday ? Icons.celebration_outlined : Icons.beach_access_outlined,
                  size: 19,
                  color: c.ink,
                ),
              )
            else
              SizedBox(
                width: 38,
                height: 38,
                child: Stack(
                  alignment: Alignment.center,
                  children: [
                    CircularProgressIndicator(
                      value: rate,
                      strokeWidth: 3.5,
                      color: c.done,
                      backgroundColor: c.track,
                      strokeCap: StrokeCap.round,
                    ),
                    Text(
                      '$done/${list.length}',
                      style: TextStyle(fontSize: 10.5, fontWeight: FontWeight.w700, color: c.ink),
                    ),
                  ],
                ),
              ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    rel == 'Today' || rel == 'Yesterday' ? rel : DateFormat('EEEE').format(d),
                    style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
                  ),
                  Text(
                    parts.join(' · '),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: 12.5, color: c.muted),
                  ),
                ],
              ),
            ),
            Text(DateFormat('d MMM').format(d), style: TextStyle(fontSize: 12.5, color: c.muted)),
          ],
        ),
      ),
    );
  }

  void _showDay(BuildContext context, String day) {
    final sprint = SprintState.instance;
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (c) {
        final col = SprintColors.of(c);
        final list = sprint.tasksFor(day);
        return SafeArea(
          child: ConstrainedBox(
            constraints: BoxConstraints(maxHeight: MediaQuery.of(c).size.height * 0.8),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(24, 0, 24, 6),
                  child: Text(
                    DateFormat('EEEE, d MMMM').format(DateTime.parse(day)),
                    style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w600),
                  ),
                ),
                Flexible(
                  child: ListView(
                    shrinkWrap: true,
                    children: [
                      for (final t in list)
                        ListTile(
                          dense: true,
                          leading: Icon(
                            switch (t.status) {
                              TaskStatus.done => Icons.check_circle_rounded,
                              TaskStatus.notDone => Icons.cancel_rounded,
                              TaskStatus.paused => Icons.pause_circle_rounded,
                              _ => Icons.radio_button_unchecked_rounded,
                            },
                            color: switch (t.status) {
                              TaskStatus.done => col.done,
                              TaskStatus.notDone => col.notDone,
                              TaskStatus.paused => col.paused,
                              _ => col.muted,
                            },
                          ),
                          title: Text(t.text, style: const TextStyle(fontSize: 15)),
                          subtitle: Text(switch (t.status) {
                            TaskStatus.done => 'Done',
                            TaskStatus.notDone => t.movedId != null ? 'Not done · moved to next day' : 'Not done',
                            TaskStatus.paused => 'Paused',
                            _ => 'Not updated',
                          }, style: const TextStyle(fontSize: 12.5)),
                        ),
                    ],
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 6, 20, 12),
                  child: SizedBox(
                    width: double.infinity,
                    child: OutlinedButton(
                      style: OutlinedButton.styleFrom(
                        minimumSize: const Size(0, 44),
                        textStyle: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
                      ),
                      onPressed: () {
                        Navigator.pop(c);
                        Navigator.of(context).push(MaterialPageRoute(builder: (_) => ReviewScreen(date: day)));
                      },
                      child: const Text('Change status'),
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

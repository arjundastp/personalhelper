import 'package:intl/intl.dart';
import 'package:material_ui/material_ui.dart';

import '../format.dart' show fmtDay, fmtTime;
import '../sprint/insights_view.dart' show SprintColors;
import '../sprint/review_screen.dart';
import '../sprint/sprint_state.dart';
import '../sprint/sprint_stats.dart';
import '../state.dart';
import '../team/team_state.dart';
import 'history_screen.dart';

/// The first screen: a warm greeting, what needs you today, and your most efficient day.
/// Everything is worked out on the phone from reminders, Daily Sprint and the Team summary.
class LandingScreen extends StatelessWidget {
  /// Switches the bottom menu to 'reminders', 'sprint' or 'team'.
  final void Function(String tab) onOpenTab;
  const LandingScreen({super.key, required this.onOpenTab});

  @override
  Widget build(BuildContext context) {
    final app = AppState.instance;
    final sprint = SprintState.instance;
    final team = TeamState.instance;
    return ListenableBuilder(
      listenable: Listenable.merge([app, sprint, team]),
      builder: (context, _) {
        final now = sprint.now();
        final c = SprintColors.of(context);
        final attention = _attention(context, now);
        return Scaffold(
          body: SafeArea(
            child: ListView(
              padding: const EdgeInsets.fromLTRB(14, 12, 14, 24),
              children: [
                _Greeting(now: now),
                const SizedBox(height: 16),
                _SectionTitle('Needs your attention', count: attention.length),
                if (attention.isEmpty)
                  _Card(
                    child: Row(
                      children: [
                        Icon(Icons.check_circle_rounded, color: c.done, size: 22),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Text('All clear. Nothing needs you right now.', style: TextStyle(fontSize: 14.5, color: c.ink)),
                        ),
                      ],
                    ),
                  )
                else
                  _Card(
                    padding: EdgeInsets.zero,
                    child: Column(
                      children: [
                        for (var i = 0; i < attention.length; i++) ...[
                          if (i > 0) Divider(height: 1, indent: 52, color: Theme.of(context).colorScheme.outlineVariant),
                          attention[i],
                        ],
                      ],
                    ),
                  ),
                if (sprint.enabled) ...[
                  const SizedBox(height: 16),
                  const _SectionTitle('Your most efficient day'),
                  _Efficiency(stats: SprintStats(sprint), onOpen: () => onOpenTab('sprint')),
                ],
                const SizedBox(height: 16),
                const _SectionTitle('Today at a glance'),
                _Glance(onOpenTab: onOpenTab),
              ],
            ),
          ),
        );
      },
    );
  }

  /// Most important first: things that can be missed, then things people are waiting on, then plans.
  List<Widget> _attention(BuildContext context, DateTime now) {
    final app = AppState.instance;
    final sprint = SprintState.instance;
    final team = TeamState.instance;
    void push(Widget w) => Navigator.of(context).push(MaterialPageRoute(builder: (_) => w));
    final out = <Widget>[];

    if (app.missingCritical.isNotEmpty) {
      out.add(
        _AttentionRow(
          icon: Icons.warning_amber_rounded,
          color: const Color(0xFFD93025),
          title: 'Reminders may not ring',
          subtitle: 'A permission is off. Tap to fix it.',
          onTap: () => onOpenTab('reminders'),
        ),
      );
    }
    final missed = app.unseenMissed;
    if (missed > 0) {
      out.add(
        _AttentionRow(
          icon: Icons.alarm_off_rounded,
          color: const Color(0xFFD93025),
          title: '$missed missed reminder${missed == 1 ? '' : 's'}',
          subtitle: 'See what you missed',
          onTap: () => push(const HistoryScreen()),
        ),
      );
    }

    // People waiting on you (Team summary), Pulse first.
    if (team.enabled && team.summaries.isNotEmpty) {
      final s = team.summaries.first;
      final actions = [...s.actions]..sort((a, b) => (_isPulse(b.text) ? 1 : 0) - (_isPulse(a.text) ? 1 : 0));
      for (final a in actions.take(3)) {
        out.add(
          _AttentionRow(
            icon: _isPulse(a.text) ? Icons.monitor_heart_outlined : Icons.forum_outlined,
            color: const Color(0xFFE5773A),
            title: a.text,
            subtitle: [a.source, if (s.date != sprint.today) _ago(s.date)].where((e) => e.isNotEmpty).join(' · '),
            onTap: () => onOpenTab('team'),
          ),
        );
      }
      if (actions.length > 3) {
        out.add(
          _AttentionRow(
            icon: Icons.more_horiz_rounded,
            color: const Color(0xFFE5773A),
            title: '${actions.length - 3} more from Teams',
            subtitle: 'Open the Team summary',
            onTap: () => onOpenTab('team'),
          ),
        );
      }
    }

    if (sprint.enabled) {
      final day = sprint.unansweredDay;
      if (day != null) {
        final open = sprint.tasksFor(day).where((t) => t.status == TaskStatus.open).length;
        out.add(
          _AttentionRow(
            icon: Icons.event_busy_rounded,
            color: const Color(0xFF3E63DD),
            title: '${fmtDay(DateTime.parse(day))}\'s tasks are not updated',
            subtitle: '$open task${open == 1 ? '' : 's'} without an answer',
            onTap: () => push(ReviewScreen(date: day)),
          ),
        );
      }
      final openToday = sprint.openToday();
      final evening = now.hour * 60 + now.minute >= sprint.eveningMin;
      if (openToday > 0 && evening && sprint.leaveOn(sprint.today)?.fullDayOff != true) {
        out.add(
          _AttentionRow(
            icon: Icons.fact_check_outlined,
            color: const Color(0xFF3E63DD),
            title: 'How did today go?',
            subtitle: '$openToday task${openToday == 1 ? '' : 's'} to update',
            onTap: () => push(ReviewScreen(date: sprint.today)),
          ),
        );
      }
      // Goals with a target date in the next 14 days (or overdue) that are not finished.
      final soon = DateTime(now.year, now.month, now.day).add(const Duration(days: 14));
      for (final g in sprint.goals.where((g) => g.status == GoalStatus.active && g.targetDate != null && g.progress < 100)) {
        final target = DateTime.parse(g.targetDate!);
        if (target.isAfter(soon)) continue;
        final overdue = target.isBefore(DateTime(now.year, now.month, now.day));
        out.add(
          _AttentionRow(
            icon: Icons.flag_outlined,
            color: const Color(0xFF8E44AD),
            title: g.title,
            subtitle: '${overdue ? 'Target passed' : 'Target ${fmtDay(target)}'} · ${g.progress}% done',
            onTap: () => onOpenTab('sprint'),
          ),
        );
      }
    }
    return out;
  }

  static bool _isPulse(String text) => text.toLowerCase().contains('pulse');

  static String _ago(String iso) {
    final d = DateTime.parse(iso);
    return fmtDay(d) == 'Yesterday' ? 'from yesterday' : 'from ${DateFormat('EEE d MMM').format(d)}';
  }
}

// ------------------------------------------------------------------ greeting

class _Greeting extends StatelessWidget {
  final DateTime now;
  const _Greeting({required this.now});

  static const _lines = [
    'Small steps still move you forward.',
    'One thing at a time. You have got this.',
    'Be proud of how far you have come.',
    'Make today count, and be kind to yourself.',
    'Progress, not perfection.',
    'A calm mind gets more done.',
    'Start with the one task that matters most.',
  ];

  String get _hello {
    final h = now.hour;
    if (h >= 5 && h < 12) return 'Good morning';
    if (h >= 12 && h < 17) return 'Good afternoon';
    if (h >= 17 && h < 22) return 'Good evening';
    return 'Hello';
  }

  IconData get _icon {
    final h = now.hour;
    if (h >= 5 && h < 12) return Icons.wb_sunny_rounded;
    if (h >= 12 && h < 17) return Icons.wb_cloudy_rounded;
    return Icons.nights_stay_rounded;
  }

  String _line(SprintState sprint) {
    final leave = sprint.enabled ? sprint.leaveOn(sprint.today) : null;
    if (leave?.fullDayOff == true) return 'Enjoy your day off. Everything can wait.';
    if (sprint.enabled && now.hour >= 17) {
      final list = sprint.tasksFor(sprint.today);
      final done = list.where((t) => t.status == TaskStatus.done).length;
      if (list.isNotEmpty && done == list.length) return 'Everything on today\'s plan is done. Well earned rest!';
    }
    if (now.weekday == DateTime.monday && now.hour < 12) return 'A fresh week begins. Set the tone today.';
    if (now.weekday == DateTime.friday) return 'Happy Friday! Finish strong.';
    if (now.weekday >= DateTime.saturday) return 'Slow down and recharge this weekend.';
    final dayOfYear = now.difference(DateTime(now.year)).inDays;
    return _lines[dayOfYear % _lines.length];
  }

  Future<void> _editName(BuildContext context) async {
    final app = AppState.instance;
    final ctrl = TextEditingController(text: app.setting<String>('userName', ''));
    final name = await showDialog<String>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('What should we call you?', style: TextStyle(fontSize: 18)),
        content: TextField(
          controller: ctrl,
          autofocus: true,
          textCapitalization: TextCapitalization.words,
          decoration: const InputDecoration(hintText: 'Your first name'),
          onSubmitted: (v) => Navigator.pop(c, v),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c), child: const Text('Cancel')),
          TextButton(onPressed: () => Navigator.pop(c, ctrl.text), child: const Text('Save')),
        ],
      ),
    );
    if (name != null) await app.updateSettings({'userName': name.trim()});
  }

  @override
  Widget build(BuildContext context) {
    final app = AppState.instance;
    final sprint = SprintState.instance;
    final name = app.setting<String>('userName', '').trim();
    return Container(
      padding: const EdgeInsets.fromLTRB(18, 16, 18, 18),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(20),
        gradient: const LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight, colors: [Color(0xFF008069), Color(0xFF00A884)]),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(DateFormat('EEEE, d MMMM').format(now), style: const TextStyle(fontSize: 13.5, color: Color(0xE6FFFFFF))),
              ),
              Icon(_icon, color: const Color(0xFFFFE08A), size: 22),
            ],
          ),
          const SizedBox(height: 6),
          InkWell(
            onTap: () => _editName(context),
            borderRadius: BorderRadius.circular(8),
            child: Text(
              name.isEmpty ? '$_hello!' : '$_hello, $name!',
              style: const TextStyle(fontSize: 25, fontWeight: FontWeight.w700, color: Colors.white, height: 1.2),
            ),
          ),
          const SizedBox(height: 6),
          Text(_line(sprint), style: const TextStyle(fontSize: 15, color: Colors.white, height: 1.35)),
          if (name.isEmpty) ...[
            const SizedBox(height: 10),
            InkWell(
              onTap: () => _editName(context),
              borderRadius: BorderRadius.circular(20),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                decoration: BoxDecoration(color: const Color(0x33FFFFFF), borderRadius: BorderRadius.circular(20)),
                child: const Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.waving_hand_outlined, size: 16, color: Colors.white),
                    SizedBox(width: 6),
                    Text(
                      'Add your name',
                      style: TextStyle(fontSize: 13, color: Colors.white, fontWeight: FontWeight.w600),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

// ------------------------------------------------------------------ efficiency

class _Efficiency extends StatelessWidget {
  final SprintStats stats;
  final VoidCallback onOpen;
  const _Efficiency({required this.stats, required this.onOpen});

  static const _names = ['', 'Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday', 'Saturday', 'Sunday'];
  static const _short = ['', 'M', 'T', 'W', 'T', 'F', 'S', 'S'];

  @override
  Widget build(BuildContext context) {
    final c = SprintColors.of(context);
    final best = stats.bestWeekday();
    final day = stats.bestDay();
    if (best == null && day == null) {
      return _Card(
        child: Text(
          'Plan and update a few days in Daily Sprint, and DayMate will show which day you get the most done.',
          style: TextStyle(fontSize: 14, color: c.muted, height: 1.4),
        ),
      );
    }
    final rates = stats.weekdayRates;
    return _Card(
      onTap: onOpen,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (best != null) ...[
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(color: c.done.withValues(alpha: 0.15), shape: BoxShape.circle),
                  child: Icon(Icons.bolt_rounded, color: c.done, size: 24),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '${_names[best.weekday]}s',
                        style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700, color: c.ink),
                      ),
                      Text(
                        'You finish ${(best.rate * 100).round()}% of your tasks on ${_names[best.weekday]}s (last 8 weeks).',
                        style: TextStyle(fontSize: 13.5, color: c.muted, height: 1.35),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 14),
            SizedBox(
              height: 70,
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  for (var w = 1; w <= 7; w++)
                    Expanded(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.end,
                        children: [
                          Container(
                            height: 4 + 44 * (rates[w] ?? 0),
                            margin: const EdgeInsets.symmetric(horizontal: 7),
                            decoration: BoxDecoration(
                              color: rates[w] == null ? c.track : (w == best.weekday ? c.done : c.done.withValues(alpha: 0.35)),
                              borderRadius: BorderRadius.circular(4),
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            _short[w],
                            style: TextStyle(
                              fontSize: 12,
                              color: w == best.weekday ? c.ink : c.muted,
                              fontWeight: w == best.weekday ? FontWeight.w700 : FontWeight.w400,
                            ),
                          ),
                        ],
                      ),
                    ),
                ],
              ),
            ),
          ],
          if (day != null) ...[
            if (best != null) const SizedBox(height: 12),
            Row(
              children: [
                Icon(Icons.emoji_events_outlined, size: 18, color: const Color(0xFFE0A100)),
                const SizedBox(width: 8),
                Expanded(
                  child: Text.rich(
                    TextSpan(
                      children: [
                        const TextSpan(
                          text: 'Best day this month: ',
                          style: TextStyle(fontWeight: FontWeight.w600),
                        ),
                        TextSpan(
                          text:
                              '${DateFormat('EEE d MMM').format(day.day)} · ${day.done} of ${day.total} done'
                              '${day.partial > 0 ? ', ${day.partial} partly' : ''}',
                        ),
                      ],
                    ),
                    style: TextStyle(fontSize: 13.5, color: c.ink),
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

// ------------------------------------------------------------------ today at a glance

class _Glance extends StatelessWidget {
  final void Function(String tab) onOpenTab;
  const _Glance({required this.onOpenTab});

  @override
  Widget build(BuildContext context) {
    final app = AppState.instance;
    final sprint = SprintState.instance;
    final team = TeamState.instance;
    final now = sprint.now();
    final next = app.upcoming.where((r) => r.nextAlert!.isAfter(now)).toList();
    final todayEnd = DateTime(now.year, now.month, now.day + 1);
    final laterToday = next.where((r) => r.nextAlert!.isBefore(todayEnd)).length;
    final rows = <Widget>[
      _GlanceRow(
        icon: Icons.notifications_none_rounded,
        title: next.isEmpty ? 'No reminders coming up' : 'Next: ${next.first.title}',
        value: next.isEmpty
            ? ''
            : '${fmtDay(next.first.nextAlert!) == 'Today' ? fmtTime(context, next.first.nextAlert!) : '${fmtDay(next.first.nextAlert!)}, ${fmtTime(context, next.first.nextAlert!)}'}'
                  '${laterToday > 1 ? ' · ${laterToday - 1} more today' : ''}',
        onTap: () => onOpenTab('reminders'),
      ),
    ];
    if (sprint.enabled) {
      final list = sprint.tasksFor(sprint.today);
      final done = list.where((t) => t.status == TaskStatus.done).length;
      final leave = sprint.leaveOn(sprint.today);
      rows.add(
        _GlanceRow(
          icon: Icons.assignment_outlined,
          title: leave != null
              ? leave.label
              : list.isEmpty
              ? 'No tasks planned yet'
              : '$done of ${list.length} tasks done',
          value: list.isEmpty && leave == null ? 'Tap to plan your day' : (sprint.streak > 1 ? '${sprint.streak}-day streak' : ''),
          onTap: () => onOpenTab('sprint'),
        ),
      );
    }
    if (team.enabled) {
      final s = team.summaries.isEmpty ? null : team.summaries.first;
      rows.add(
        _GlanceRow(
          icon: Icons.forum_outlined,
          title: s == null ? 'No Teams summary yet' : 'Teams summary for ${fmtDay(DateTime.parse(s.date)).toLowerCase()}',
          value: s == null ? 'Arrives after your Claude routine runs' : '${s.chats.length} chat${s.chats.length == 1 ? '' : 's'} · ${s.actions.length} for you',
          onTap: () => onOpenTab('team'),
        ),
      );
    }
    return _Card(
      padding: EdgeInsets.zero,
      child: Column(
        children: [
          for (var i = 0; i < rows.length; i++) ...[if (i > 0) Divider(height: 1, indent: 52, color: Theme.of(context).colorScheme.outlineVariant), rows[i]],
        ],
      ),
    );
  }
}

// ------------------------------------------------------------------ small pieces

class _SectionTitle extends StatelessWidget {
  final String text;
  final int? count;
  const _SectionTitle(this.text, {this.count});

  @override
  Widget build(BuildContext context) {
    final c = SprintColors.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 0, 4, 8),
      child: Row(
        children: [
          Text(
            text,
            style: TextStyle(fontSize: 15.5, fontWeight: FontWeight.w700, color: c.ink),
          ),
          if (count != null && count! > 0) ...[
            const SizedBox(width: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 1),
              decoration: BoxDecoration(color: const Color(0xFFE5773A), borderRadius: BorderRadius.circular(10)),
              child: Text(
                '$count',
                style: const TextStyle(fontSize: 12, color: Colors.white, fontWeight: FontWeight.w700),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _Card extends StatelessWidget {
  final Widget child;
  final EdgeInsets padding;
  final VoidCallback? onTap;
  const _Card({required this.child, this.padding = const EdgeInsets.all(14), this.onTap});

  @override
  Widget build(BuildContext context) {
    final c = SprintColors.of(context);
    return Material(
      color: c.card,
      borderRadius: BorderRadius.circular(16),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(padding: padding, child: child),
      ),
    );
  }
}

class _AttentionRow extends StatelessWidget {
  final IconData icon;
  final Color color;
  final String title;
  final String subtitle;
  final VoidCallback onTap;
  const _AttentionRow({required this.icon, required this.color, required this.title, required this.subtitle, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final c = SprintColors.of(context);
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 11, 10, 11),
        child: Row(
          children: [
            Container(
              width: 30,
              height: 30,
              decoration: BoxDecoration(color: color.withValues(alpha: 0.14), shape: BoxShape.circle),
              child: Icon(icon, size: 17, color: color),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: 14, color: c.ink, height: 1.3),
                  ),
                  if (subtitle.isNotEmpty)
                    Text(
                      subtitle,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(fontSize: 12, color: c.muted),
                    ),
                ],
              ),
            ),
            Icon(Icons.chevron_right_rounded, color: c.muted, size: 20),
          ],
        ),
      ),
    );
  }
}

class _GlanceRow extends StatelessWidget {
  final IconData icon;
  final String title;
  final String value;
  final VoidCallback onTap;
  const _GlanceRow({required this.icon, required this.title, required this.value, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final c = SprintColors.of(context);
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 11, 10, 11),
        child: Row(
          children: [
            Icon(icon, size: 22, color: c.muted),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: 14.5, color: c.ink),
                  ),
                  if (value.isNotEmpty)
                    Text(
                      value,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(fontSize: 12.5, color: c.muted),
                    ),
                ],
              ),
            ),
            Icon(Icons.chevron_right_rounded, color: c.muted, size: 20),
          ],
        ),
      ),
    );
  }
}

import 'package:intl/intl.dart';
import 'package:material_ui/material_ui.dart';

import '../main.dart' show AppColors;
import '../widgets.dart';
import 'insights_view.dart' show SprintColors;
import 'review_export.dart' show categoryLabel;
import 'sprint_state.dart';

String _relDate(String iso) {
  final d = DateTime.parse(iso);
  final days = DateTime.now().difference(DateTime(d.year, d.month, d.day)).inDays;
  if (days <= 0) return 'today';
  if (days == 1) return 'yesterday';
  if (days < 30) return '$days days ago';
  return DateFormat('d MMM').format(d);
}

/// The "Goals" tab: long-term goals with a progress bar each.
class GoalsView extends StatelessWidget {
  const GoalsView({super.key});

  @override
  Widget build(BuildContext context) {
    final s = SprintState.instance;
    return ListenableBuilder(
      listenable: s,
      builder: (context, _) {
        final c = SprintColors.of(context);
        final active = s.goals.where((g) => g.status == GoalStatus.active).toList()
          ..sort((a, b) => (a.targetDate ?? '9999').compareTo(b.targetDate ?? '9999'));
        final finished = s.goals.where((g) => g.status != GoalStatus.active).toList();
        return Column(children: [
          Expanded(
            child: s.goals.isEmpty
                ? Center(
                    child: Padding(
                      padding: const EdgeInsets.all(32),
                      child: Column(mainAxisSize: MainAxisSize.min, children: [
                        Icon(Icons.flag_outlined, size: 48, color: c.muted.withValues(alpha: 0.5)),
                        const SizedBox(height: 10),
                        Text('No goals yet.\nAdd a long-term goal and log progress notes as you go.',
                            textAlign: TextAlign.center, style: TextStyle(fontSize: 14.5, color: c.muted, height: 1.4)),
                      ]),
                    ),
                  )
                : ListView(
                    padding: const EdgeInsets.fromLTRB(14, 6, 14, 16),
                    children: [
                      if (active.isNotEmpty) const ListHeader('In progress', left: 4),
                      for (final g in active) _GoalCard(goal: g),
                      if (finished.isNotEmpty) const ListHeader('Completed & dropped', left: 4),
                      for (final g in finished) _GoalCard(goal: g),
                    ],
                  ),
          ),
          BottomAddBar(label: 'Add a goal', icon: Icons.flag_outlined, onTap: () => showGoalSheet(context)),
        ]);
      },
    );
  }
}

class _GoalCard extends StatelessWidget {
  final Goal goal;
  const _GoalCard({required this.goal});

  @override
  Widget build(BuildContext context) {
    final c = SprintColors.of(context);
    final g = goal;
    final done = g.status == GoalStatus.done;
    final dropped = g.status == GoalStatus.dropped;
    final meta = [
      if (done) 'Completed',
      if (dropped) 'Dropped',
      if (!done && !dropped && g.targetDate != null) 'Target ${DateFormat('d MMM y').format(DateTime.parse(g.targetDate!))}',
      g.lastUpdate == null ? 'No updates yet' : 'Updated ${_relDate(g.lastUpdate!)}',
    ].join(' · ');
    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: Material(
        color: c.card,
        borderRadius: BorderRadius.circular(14),
        child: InkWell(
          borderRadius: BorderRadius.circular(14),
          onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => GoalDetailScreen(goalId: g.id))),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                Expanded(
                  child: Text(g.title,
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                        color: dropped ? c.muted : c.ink,
                        decoration: dropped ? TextDecoration.lineThrough : null,
                      )),
                ),
                Text('${g.progress}%', style: TextStyle(fontSize: 13.5, fontWeight: FontWeight.w700, color: c.ink)),
              ]),
              const SizedBox(height: 8),
              ClipRRect(
                borderRadius: BorderRadius.circular(3),
                child: LinearProgressIndicator(
                  value: g.progress / 100,
                  minHeight: 6,
                  color: dropped ? c.muted : c.done,
                  backgroundColor: c.track,
                ),
              ),
              const SizedBox(height: 7),
              Text(meta, style: TextStyle(fontSize: 12, color: c.muted)),
            ]),
          ),
        ),
      ),
    );
  }
}

/// One goal: progress, why, progress notes (timeline) and linked achievements.
class GoalDetailScreen extends StatefulWidget {
  final int goalId;
  const GoalDetailScreen({super.key, required this.goalId});

  @override
  State<GoalDetailScreen> createState() => _GoalDetailScreenState();
}

class _GoalDetailScreenState extends State<GoalDetailScreen> {
  final s = SprintState.instance;

  Future<void> _addNote(Goal g) async {
    final text = TextEditingController();
    var progress = g.progress.toDouble();
    final ok = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      builder: (c) => StatefulBuilder(
        builder: (c, set) => Padding(
          padding: EdgeInsets.only(bottom: MediaQuery.of(c).viewInsets.bottom),
          child: SafeArea(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
              child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
                const Text('Progress note', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w600)),
                const SizedBox(height: 8),
                TextField(
                  controller: text,
                  autofocus: true,
                  minLines: 2,
                  maxLines: 5,
                  textCapitalization: TextCapitalization.sentences,
                  style: const TextStyle(fontSize: 15),
                  decoration: const InputDecoration(hintText: 'What moved forward? e.g. Finished module 3'),
                ),
                const SizedBox(height: 14),
                Row(children: [
                  const Text('Progress', style: TextStyle(fontSize: 14)),
                  const Spacer(),
                  Text('${progress.round()}%', style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700)),
                ]),
                Slider(
                  value: progress,
                  min: 0,
                  max: 100,
                  divisions: 20,
                  label: '${progress.round()}%',
                  onChanged: (v) => set(() => progress = v),
                ),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton(onPressed: () => Navigator.pop(c, true), child: const Text('Save note')),
                ),
              ]),
            ),
          ),
        ),
      ),
    );
    if (ok != true) return;
    final p = progress.round();
    await s.addGoalNote(g.id, text.text, progress: p != g.progress ? p : null);
    if (p >= 100 && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Goal completed. Well done!')));
    }
  }

  Future<void> _menu(Goal g) async {
    final choice = await showModalBottomSheet<String>(
      context: context,
      builder: (c) => SafeArea(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          OptionRow(icon: Icons.edit_outlined, title: 'Edit goal', onTap: () => Navigator.pop(c, 'edit')),
          if (g.status != GoalStatus.done)
            OptionRow(icon: Icons.emoji_events_outlined, title: 'Mark completed', onTap: () => Navigator.pop(c, 'done')),
          if (g.status != GoalStatus.active)
            OptionRow(icon: Icons.replay_rounded, title: 'Make active again', onTap: () => Navigator.pop(c, 'active')),
          if (g.status == GoalStatus.active)
            OptionRow(icon: Icons.do_not_disturb_on_outlined, title: 'Drop this goal', onTap: () => Navigator.pop(c, 'drop')),
          OptionRow(icon: Icons.delete_outline_rounded, title: 'Delete', color: AppColors.red, onTap: () => Navigator.pop(c, 'delete')),
          const SizedBox(height: 6),
        ]),
      ),
    );
    if (!mounted) return;
    switch (choice) {
      case 'edit':
        await showGoalSheet(context, goal: g);
      case 'done':
        await s.setGoalStatus(g.id, GoalStatus.done);
      case 'active':
        await s.setGoalStatus(g.id, GoalStatus.active);
      case 'drop':
        await s.setGoalStatus(g.id, GoalStatus.dropped);
      case 'delete':
        final ok = await showDialog<bool>(
          context: context,
          builder: (c) => AlertDialog(
            title: const Text('Delete this goal?'),
            content: const Text('Its progress notes are deleted too. Linked achievements are kept.'),
            actions: [
              TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Cancel')),
              TextButton(
                style: TextButton.styleFrom(foregroundColor: AppColors.red),
                onPressed: () => Navigator.pop(c, true),
                child: const Text('Delete'),
              ),
            ],
          ),
        );
        if (ok == true) {
          await s.deleteGoal(g.id);
          if (mounted) Navigator.of(context).pop();
        }
    }
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: s,
      builder: (context, _) {
        final g = s.goalById(widget.goalId);
        if (g == null) return const Scaffold();
        final c = SprintColors.of(context);
        final linked = s.achievements.where((a) => a.goalId == g.id).toList()..sort((a, b) => b.date.compareTo(a.date));
        return Scaffold(
          appBar: AppBar(
            title: const Text('Goal'),
            actions: [IconButton(tooltip: 'More', onPressed: () => _menu(g), icon: const Icon(Icons.more_vert_rounded))],
          ),
          body: Column(children: [
            Expanded(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
                children: [
                  Text(g.title, style: TextStyle(fontSize: 19, fontWeight: FontWeight.w700, color: c.ink)),
                  if (g.why.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(top: 4),
                      child: Text(g.why, style: TextStyle(fontSize: 14, color: c.muted, height: 1.35)),
                    ),
                  const SizedBox(height: 14),
                  Container(
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(color: c.card, borderRadius: BorderRadius.circular(14)),
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Row(children: [
                        Text('${g.progress}%', style: TextStyle(fontSize: 24, fontWeight: FontWeight.w700, color: c.ink)),
                        const SizedBox(width: 8),
                        Text(
                          switch (g.status) {
                            GoalStatus.done => 'completed',
                            GoalStatus.dropped => 'dropped',
                            _ => 'done so far',
                          },
                          style: TextStyle(fontSize: 13, color: c.muted),
                        ),
                        const Spacer(),
                        if (g.targetDate != null)
                          Text('Target ${DateFormat('d MMM y').format(DateTime.parse(g.targetDate!))}',
                              style: TextStyle(fontSize: 12.5, color: c.muted)),
                      ]),
                      const SizedBox(height: 8),
                      ClipRRect(
                        borderRadius: BorderRadius.circular(4),
                        child: LinearProgressIndicator(value: g.progress / 100, minHeight: 8, color: c.done, backgroundColor: c.track),
                      ),
                      const SizedBox(height: 6),
                      Text('Started ${DateFormat('d MMM y').format(DateTime.parse(g.createdOn))} · ${g.notes.length} note${g.notes.length == 1 ? '' : 's'}',
                          style: TextStyle(fontSize: 12, color: c.muted)),
                    ]),
                  ),
                  const SizedBox(height: 6),
                  const ListHeader('Progress notes', left: 0),
                  if (g.notes.isEmpty)
                    Padding(
                      padding: const EdgeInsets.fromLTRB(4, 4, 4, 8),
                      child: Text('No notes yet. Add one whenever something moves forward.',
                          style: TextStyle(fontSize: 13.5, color: c.muted)),
                    ),
                  for (var i = 0; i < g.notes.length; i++) _NoteTile(note: g.notes[i], last: i == g.notes.length - 1, onDelete: () => s.deleteGoalNote(g.id, i)),
                  if (linked.isNotEmpty) ...[
                    const ListHeader('Linked achievements', left: 0),
                    for (final a in linked)
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 4),
                        child: Row(children: [
                          Icon(Icons.emoji_events_outlined, size: 18, color: c.muted),
                          const SizedBox(width: 10),
                          Expanded(child: Text(a.title, style: TextStyle(fontSize: 14, color: c.ink))),
                          Text('${categoryLabel(a.category)} · ${DateFormat('d MMM').format(DateTime.parse(a.date))}',
                              style: TextStyle(fontSize: 12, color: c.muted)),
                        ]),
                      ),
                  ],
                ],
              ),
            ),
            BottomAddBar(label: 'Add progress note', icon: Icons.edit_note_rounded, onTap: () => _addNote(g)),
          ]),
        );
      },
    );
  }
}

class _NoteTile extends StatelessWidget {
  final GoalNote note;
  final bool last;
  final VoidCallback onDelete;
  const _NoteTile({required this.note, required this.last, required this.onDelete});

  @override
  Widget build(BuildContext context) {
    final c = SprintColors.of(context);
    return IntrinsicHeight(
      child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        SizedBox(
          width: 22,
          child: Column(children: [
            const SizedBox(height: 5),
            Container(width: 10, height: 10, decoration: BoxDecoration(color: c.done, shape: BoxShape.circle)),
            if (!last) Expanded(child: Container(width: 2, color: c.track)),
          ]),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: InkWell(
              onLongPress: () async {
                final ok = await showDialog<bool>(
                  context: context,
                  builder: (d) => AlertDialog(
                    title: const Text('Delete this note?'),
                    actions: [
                      TextButton(onPressed: () => Navigator.pop(d, false), child: const Text('Cancel')),
                      TextButton(onPressed: () => Navigator.pop(d, true), child: const Text('Delete')),
                    ],
                  ),
                );
                if (ok == true) onDelete();
              },
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Row(children: [
                  Text(DateFormat('EEE, d MMM y').format(DateTime.parse(note.date)),
                      style: TextStyle(fontSize: 12, color: c.muted, fontWeight: FontWeight.w600)),
                  if (note.progress != null) ...[
                    const SizedBox(width: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 1),
                      decoration: BoxDecoration(color: c.done.withValues(alpha: 0.15), borderRadius: BorderRadius.circular(10)),
                      child: Row(mainAxisSize: MainAxisSize.min, children: [
                        Icon(Icons.trending_up_rounded, size: 13, color: c.ink),
                        const SizedBox(width: 3),
                        Text('${note.progress}%', style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w700, color: c.ink)),
                      ]),
                    ),
                  ],
                ]),
                if (note.text.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: 2),
                    child: Text(note.text, style: TextStyle(fontSize: 14, color: c.ink, height: 1.35)),
                  ),
              ]),
            ),
          ),
        ),
      ]),
    );
  }
}

/// Add or edit a goal: title, why, optional target date.
Future<void> showGoalSheet(BuildContext context, {Goal? goal}) async {
  final s = SprintState.instance;
  final title = TextEditingController(text: goal?.title ?? '');
  final why = TextEditingController(text: goal?.why ?? '');
  String? target = goal?.targetDate;
  final ok = await showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    builder: (c) => StatefulBuilder(
      builder: (c, set) => Padding(
        padding: EdgeInsets.only(bottom: MediaQuery.of(c).viewInsets.bottom),
        child: SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
            child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(goal == null ? 'New goal' : 'Edit goal', style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w600)),
              TextField(
                controller: title,
                autofocus: goal == null,
                textCapitalization: TextCapitalization.sentences,
                style: const TextStyle(fontSize: 15.5),
                decoration: const InputDecoration(labelText: 'Goal', hintText: 'e.g. Get AWS Solutions Architect certified'),
              ),
              TextField(
                controller: why,
                minLines: 1,
                maxLines: 3,
                textCapitalization: TextCapitalization.sentences,
                style: const TextStyle(fontSize: 14.5),
                decoration: const InputDecoration(labelText: 'Why it matters (optional)'),
              ),
              const SizedBox(height: 6),
              OptionRow(
                icon: Icons.event_outlined,
                title: 'Target date',
                value: target == null ? 'None' : DateFormat('d MMM y').format(DateTime.parse(target!)),
                trailing: target == null
                    ? null
                    : IconButton(tooltip: 'No target date', onPressed: () => set(() => target = null), icon: const Icon(Icons.close_rounded)),
                onTap: () async {
                  final now = DateTime.now();
                  final d = await showDatePicker(
                    context: c,
                    initialDate: target == null ? now.add(const Duration(days: 90)) : DateTime.parse(target!),
                    firstDate: DateTime(now.year - 2),
                    lastDate: DateTime(now.year + 10),
                  );
                  if (d != null) set(() => target = DateFormat('yyyy-MM-dd').format(d));
                },
              ),
              const SizedBox(height: 8),
              SizedBox(
                width: double.infinity,
                child: FilledButton(onPressed: () => Navigator.pop(c, true), child: const Text('Save')),
              ),
            ]),
          ),
        ),
      ),
    ),
  );
  if (ok != true || title.text.trim().isEmpty) return;
  if (goal == null) {
    await s.addGoal(title.text, why: why.text, targetDate: target);
  } else {
    await s.update((_) {
      goal.title = title.text.trim();
      goal.why = why.text.trim();
      goal.targetDate = target;
    });
  }
}

/// Slim full-width "add" button at the bottom of a tab.
class BottomAddBar extends StatelessWidget {
  final String label;
  final IconData icon;
  final VoidCallback onTap;
  const BottomAddBar({super.key, required this.label, required this.icon, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final light = Theme.of(context).brightness == Brightness.light;
    return Container(
      color: light ? const Color(0xFFF0F2F5) : const Color(0xFF1F2C34),
      padding: const EdgeInsets.fromLTRB(12, 6, 12, 6),
      child: SafeArea(
        top: false,
        child: SizedBox(
          width: double.infinity,
          child: FilledButton.icon(
            style: FilledButton.styleFrom(
              minimumSize: const Size(0, 42),
              textStyle: TextStyle(fontFamily: Theme.of(context).textTheme.bodyMedium?.fontFamily, fontSize: 14.5, fontWeight: FontWeight.w600),
            ),
            onPressed: onTap,
            icon: Icon(icon, size: 20),
            label: Text(label),
          ),
        ),
      ),
    );
  }
}

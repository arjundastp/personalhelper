import 'package:intl/intl.dart';
import 'package:material_ui/material_ui.dart';

import '../format.dart' show fmtDay;
import '../main.dart' show AppColors;
import 'sprint_screen.dart' show sprintBlue, notDoneColor, partialColor;
import 'sprint_state.dart';

/// "How did today go?": one answer per task: Done, Partly done or Not done (both optionally
/// continued on the next work day) or Paused (goes to the Parked tasks list). Any task can get a note.
class ReviewScreen extends StatefulWidget {
  final String date;
  const ReviewScreen({super.key, required this.date});

  @override
  State<ReviewScreen> createState() => _ReviewScreenState();
}

class _ReviewScreenState extends State<ReviewScreen> {
  final sprint = SprintState.instance;
  late final List<SprintTask> tasks = sprint.tasksFor(widget.date);
  late final Map<int, String?> status = {
    for (final t in tasks) t.id: t.status == TaskStatus.open ? null : t.status,
  };
  late final Map<int, bool> move = {
    // A "Not done" / "Partly done" answered earlier without moving keeps that choice.
    for (final t in tasks) t.id: (t.status == TaskStatus.notDone || t.status == TaskStatus.partial) ? t.movedId != null : true,
  };
  late final Map<int, TextEditingController> notes = {for (final t in tasks) t.id: TextEditingController(text: t.note ?? '')};
  late final Set<int> noteOpen = {for (final t in tasks) if (t.note != null) t.id};
  bool saved = false;

  @override
  void dispose() {
    for (final c in notes.values) {
      c.dispose();
    }
    super.dispose();
  }

  void _pick(SprintTask t, String s) => setState(() {
    status[t.id] = s;
    if (s == TaskStatus.partial) noteOpen.add(t.id);
  });

  DateTime get date => DateTime.parse(widget.date);

  String get _nextDayLabel {
    final next = sprint.nextWorkday(date);
    final rel = fmtDay(next);
    return rel == 'Tomorrow' ? "tomorrow's plan" : "${DateFormat('EEEE').format(next)}'s plan";
  }

  Future<void> _save() async {
    await sprint.review(widget.date, {
      for (final t in tasks)
        if (status[t.id] != null) t.id: ReviewAnswer(status[t.id]!, move: move[t.id] ?? true, note: notes[t.id]!.text),
    });
    setState(() => saved = true);
  }

  @override
  Widget build(BuildContext context) {
    final grey = Theme.of(context).colorScheme.onSurfaceVariant;
    final left = tasks.where((t) => status[t.id] == null).length;
    final title = fmtDay(date) == 'Today' ? 'How did today go?' : 'How did ${fmtDay(date)} go?';
    return Scaffold(
      appBar: AppBar(title: Text(saved ? 'Day saved' : title)),
      bottomNavigationBar: saved || tasks.isEmpty
          ? null
          : SafeArea(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 8, 20, 12),
                child: FilledButton(
                  style: left > 0 ? FilledButton.styleFrom(backgroundColor: grey) : null,
                  onPressed: left > 0 ? null : _save,
                  child: Text(left > 0 ? 'Answer $left more to save' : 'Save my day'),
                ),
              ),
            ),
      body: saved
          ? _Summary(date: widget.date, onChange: () => setState(() => saved = false))
          : tasks.isEmpty
              ? Center(child: Text('Nothing was planned for this day.', style: TextStyle(fontSize: 16, color: grey)))
              : ListView(
                  padding: const EdgeInsets.only(bottom: 16),
                  children: [
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 14, 16, 4),
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Text(DateFormat('EEEE, d MMMM').format(date), style: TextStyle(fontSize: 14, color: grey)),
                        const SizedBox(height: 4),
                        Text('Choose an answer for each task. Add a note if you like.', style: TextStyle(fontSize: 13, color: grey)),
                      ]),
                    ),
                    for (final t in tasks) _answerRow(context, t),
                  ],
                ),
    );
  }

  Widget _answerRow(BuildContext context, SprintTask t) {
    final theme = Theme.of(context);
    final s = status[t.id];
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 10),
      decoration: BoxDecoration(border: Border(bottom: BorderSide(color: theme.colorScheme.outlineVariant))),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(t.text, style: const TextStyle(fontSize: 15.5, fontWeight: FontWeight.w600)),
        if (t.from != null)
          Padding(
            padding: const EdgeInsets.only(top: 2),
            child: Text(t.from!, style: const TextStyle(fontSize: 12, color: notDoneColor)),
          ),
        const SizedBox(height: 8),
        Row(children: [
          Expanded(child: _choice(Icons.check_rounded, 'Done', AppColors.accent, s == TaskStatus.done, () => _pick(t, TaskStatus.done))),
          const SizedBox(width: 6),
          Expanded(child: _choice(Icons.timelapse_rounded, 'Partly done', partialColor, s == TaskStatus.partial, () => _pick(t, TaskStatus.partial))),
        ]),
        const SizedBox(height: 6),
        Row(children: [
          Expanded(child: _choice(Icons.close_rounded, 'Not done', notDoneColor, s == TaskStatus.notDone, () => _pick(t, TaskStatus.notDone))),
          const SizedBox(width: 6),
          Expanded(child: _choice(Icons.pause_rounded, 'Paused', sprintBlue, s == TaskStatus.paused, () => _pick(t, TaskStatus.paused))),
        ]),
        if (s == TaskStatus.notDone || s == TaskStatus.partial)
          InkWell(
            onTap: () => setState(() => move[t.id] = !(move[t.id] ?? true)),
            child: Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Row(children: [
                Checkbox(
                  visualDensity: VisualDensity.compact,
                  value: move[t.id] ?? true,
                  activeColor: AppColors.accent,
                  onChanged: (v) => setState(() => move[t.id] = v ?? false),
                ),
                Expanded(
                  child: Text(
                    s == TaskStatus.partial ? 'Continue the rest in $_nextDayLabel' : 'Move to $_nextDayLabel',
                    style: const TextStyle(fontSize: 14),
                  ),
                ),
              ]),
            ),
          ),
        if (s == TaskStatus.paused)
          const Padding(
            padding: EdgeInsets.only(top: 8),
            child: Row(children: [
              Icon(Icons.inventory_2_outlined, size: 17, color: sprintBlue),
              SizedBox(width: 10),
              Text('Goes to the Parked tab', style: TextStyle(fontSize: 13, color: sprintBlue)),
            ]),
          ),
        if (noteOpen.contains(t.id))
          Padding(
            padding: const EdgeInsets.only(top: 6),
            child: TextField(
              controller: notes[t.id],
              minLines: 1,
              maxLines: 4,
              textCapitalization: TextCapitalization.sentences,
              style: const TextStyle(fontSize: 14),
              decoration: InputDecoration(
                isDense: true,
                labelText: 'Note',
                hintText: s == TaskStatus.partial ? 'What is done, what is left?' : null,
                border: const OutlineInputBorder(),
              ),
            ),
          )
        else
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton.icon(
              style: TextButton.styleFrom(padding: const EdgeInsets.symmetric(horizontal: 4), visualDensity: VisualDensity.compact),
              onPressed: () => setState(() => noteOpen.add(t.id)),
              icon: const Icon(Icons.add_rounded, size: 18),
              label: const Text('Add note', style: TextStyle(fontSize: 13)),
            ),
          ),
      ]),
    );
  }

  Widget _choice(IconData icon, String label, Color color, bool selected, VoidCallback onTap) {
    final theme = Theme.of(context);
    return Semantics(
      selected: selected,
      button: true,
      child: Material(
        color: selected ? color : Colors.transparent,
        shape: StadiumBorder(side: BorderSide(color: selected ? color : theme.colorScheme.outlineVariant, width: 1.5)),
        child: InkWell(
          customBorder: const StadiumBorder(),
          onTap: onTap,
          child: SizedBox(
            height: 36,
            child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
              Icon(icon, size: 16, color: selected ? Colors.white : theme.colorScheme.onSurfaceVariant),
              const SizedBox(width: 4),
              Flexible(
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 13.5,
                    fontWeight: FontWeight.w600,
                    color: selected ? Colors.white : theme.colorScheme.onSurface,
                  ),
                ),
              ),
            ]),
          ),
        ),
      ),
    );
  }
}

class _Summary extends StatelessWidget {
  final String date;
  final VoidCallback onChange;
  const _Summary({required this.date, required this.onChange});

  @override
  Widget build(BuildContext context) {
    final sprint = SprintState.instance;
    final grey = Theme.of(context).colorScheme.onSurfaceVariant;
    final list = sprint.tasksFor(date);
    final done = list.where((t) => t.status == TaskStatus.done).length;
    final partial = list.where((t) => t.status == TaskStatus.partial).length;
    final moved = list.where((t) => (t.status == TaskStatus.notDone || t.status == TaskStatus.partial) && t.movedId != null).length;
    final paused = list.where((t) => t.status == TaskStatus.paused).length;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Container(
            width: 112,
            height: 112,
            decoration: BoxDecoration(color: AppColors.accent.withValues(alpha: 0.15), shape: BoxShape.circle),
            child: const Icon(Icons.check_rounded, size: 60, color: AppColors.accent),
          ),
          const SizedBox(height: 20),
          const Text('Day saved', style: TextStyle(fontSize: 26, fontWeight: FontWeight.w700)),
          const SizedBox(height: 8),
          Text('$done of ${list.length} tasks done', style: const TextStyle(fontSize: 19)),
          const SizedBox(height: 6),
          if (partial > 0) Text('$partial partly done', style: TextStyle(fontSize: 16, color: grey)),
          if (moved > 0) Text('$moved continue on the next work day', style: TextStyle(fontSize: 16, color: grey)),
          if (paused > 0) Text('$paused paused – see Parked tasks', style: TextStyle(fontSize: 16, color: grey)),
          const SizedBox(height: 28),
          FilledButton(
            style: FilledButton.styleFrom(minimumSize: const Size(160, 52)),
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('OK'),
          ),
          TextButton(onPressed: onChange, child: const Text('Change answers')),
        ]),
      ),
    );
  }
}

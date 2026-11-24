import 'package:intl/intl.dart';
import 'package:material_ui/material_ui.dart';

import '../format.dart' show fmtDay, fmtMinutesOfDay;
import '../main.dart' show AppColors;
import '../models.dart' show isoDate, dateOnly;
import '../widgets.dart';
import 'parked_screen.dart';
import 'review_screen.dart';
import 'sprint_history_screen.dart';
import 'sprint_settings_screen.dart';
import 'sprint_state.dart';

const sprintBlue = Color(0xFF3E63DD);
const notDoneColor = Color(0xFFC2410C);

/// The "Daily Sprint" tab: one day's plan, with a message-style box to add tasks.
class SprintScreen extends StatefulWidget {
  const SprintScreen({super.key});

  @override
  State<SprintScreen> createState() => _SprintScreenState();
}

class _SprintScreenState extends State<SprintScreen> {
  final sprint = SprintState.instance;
  final input = TextEditingController();
  final focus = FocusNode();
  late DateTime day = dateOnly(DateTime.now());

  @override
  void dispose() {
    input.dispose();
    focus.dispose();
    super.dispose();
  }

  String get dayKey => isoDate(day);
  bool get isToday => dayKey == isoDate(DateTime.now());
  bool get isPast => dayKey.compareTo(isoDate(DateTime.now())) < 0;

  void _open(Widget w) => Navigator.of(context).push(MaterialPageRoute(builder: (_) => w));

  Future<void> _add() async {
    final text = input.text;
    if (text.trim().isEmpty) return;
    input.clear();
    await sprint.add(dayKey, text);
  }

  Future<void> _taskMenu(SprintTask t) async {
    final choice = await showModalBottomSheet<String>(
      context: context,
      builder: (c) => SafeArea(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(24, 0, 24, 8),
            child: Text(t.text, style: const TextStyle(fontSize: 19, fontWeight: FontWeight.w600)),
          ),
          OptionRow(icon: Icons.edit_rounded, title: 'Change text', onTap: () => Navigator.pop(c, 'edit')),
          if (t.status != TaskStatus.paused)
            OptionRow(
              icon: Icons.pause_rounded,
              title: 'Pause – move to Parked tasks',
              onTap: () => Navigator.pop(c, 'pause'),
            ),
          OptionRow(icon: Icons.delete_rounded, title: 'Delete', color: AppColors.red, onTap: () => Navigator.pop(c, 'delete')),
          const SizedBox(height: 8),
        ]),
      ),
    );
    if (!mounted) return;
    switch (choice) {
      case 'edit':
        final text = await editTextDialog(context, title: 'Change task', initial: t.text);
        if (text != null) await sprint.rename(t.id, text);
      case 'pause':
        await sprint.pause(t.id);
        _toast('Paused. You can find it in Parked tasks.');
      case 'delete':
        await sprint.delete(t.id);
        _toast('Task deleted');
    }
  }

  void _toast(String text) {
    final m = ScaffoldMessenger.of(context);
    m.clearSnackBars();
    m.showSnackBar(SnackBar(content: Text(text, style: const TextStyle(fontSize: 16))));
  }

  String _dayTitle() {
    final rel = fmtDay(day);
    return rel == 'Today' || rel == 'Tomorrow' || rel == 'Yesterday' ? rel : DateFormat('EEEE').format(day);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final grey = theme.colorScheme.onSurfaceVariant;
    final light = theme.brightness == Brightness.light;
    return ListenableBuilder(
      listenable: sprint,
      builder: (context, _) {
        final list = sprint.tasksFor(dayKey);
        final done = list.where((t) => t.status == TaskStatus.done).length;
        final open = list.where((t) => t.status == TaskStatus.open).length;
        final carryDay = isToday ? sprint.unansweredDay : null;
        final carryCount = carryDay == null ? 0 : sprint.tasksFor(carryDay).where((t) => t.status == TaskStatus.open).length;
        final workday = sprint.workdays.contains(day.weekday);

        return Scaffold(
          appBar: AppBar(
            title: const Text('Daily Sprint'),
            actions: [
              IconButton(
                tooltip: 'Past days',
                onPressed: () => _open(const SprintHistoryScreen()),
                icon: const Icon(Icons.history_rounded),
              ),
              PopupMenuButton<String>(
                tooltip: 'More',
                onSelected: (v) => _open(switch (v) {
                  'parked' => const ParkedScreen(),
                  'history' => const SprintHistoryScreen(),
                  _ => const SprintSettingsScreen(),
                }),
                itemBuilder: (_) => const [
                  PopupMenuItem(value: 'parked', child: Text('Parked tasks', style: TextStyle(fontSize: 16))),
                  PopupMenuItem(value: 'history', child: Text('Past days', style: TextStyle(fontSize: 16))),
                  PopupMenuItem(value: 'settings', child: Text('Daily Sprint settings', style: TextStyle(fontSize: 16))),
                ],
              ),
            ],
          ),
          body: Column(children: [
            Expanded(
              child: ListView(
                padding: const EdgeInsets.only(bottom: 16),
                children: [
                  // ---- day switcher ----
                  Padding(
                    padding: const EdgeInsets.fromLTRB(4, 6, 4, 0),
                    child: Row(children: [
                      IconButton(
                        tooltip: 'Previous day',
                        iconSize: 28,
                        onPressed: () => setState(() => day = day.subtract(const Duration(days: 1))),
                        icon: const Icon(Icons.chevron_left_rounded),
                      ),
                      Expanded(
                        child: InkWell(
                          borderRadius: BorderRadius.circular(12),
                          onTap: isToday ? null : () => setState(() => day = dateOnly(DateTime.now())),
                          child: Padding(
                            padding: const EdgeInsets.symmetric(vertical: 4),
                            child: Column(children: [
                              Text(_dayTitle(), style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w600)),
                              Text(DateFormat('EEEE, d MMMM').format(day), style: TextStyle(fontSize: 14, color: grey)),
                              if (!isToday)
                                Text('Tap to go back to today',
                                    style: TextStyle(fontSize: 12.5, color: light ? AppColors.green : AppColors.accent)),
                            ]),
                          ),
                        ),
                      ),
                      IconButton(
                        tooltip: 'Next day',
                        iconSize: 28,
                        onPressed: () => setState(() => day = day.add(const Duration(days: 1))),
                        icon: const Icon(Icons.chevron_right_rounded),
                      ),
                    ]),
                  ),

                  // ---- progress ----
                  if (list.isNotEmpty)
                    _ProgressCard(
                      done: done,
                      total: list.length,
                      footer: isToday && sprint.eveningOn && workday && open > 0 && !_eveningPassed()
                          ? 'I\'ll ask you how it went at ${fmtMinutesOfDay(context, sprint.eveningMin)}'
                          : null,
                      action: (isPast || isToday) && list.isNotEmpty
                          ? (open > 0 ? 'Update status ($open left)' : 'Change status')
                          : null,
                      onAction: () => _open(ReviewScreen(date: dayKey)),
                    ),

                  // ---- parked ----
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 10, 16, 0),
                    child: Material(
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16),
                        side: BorderSide(color: theme.colorScheme.outlineVariant, width: 1.5),
                      ),
                      color: Colors.transparent,
                      child: InkWell(
                        borderRadius: BorderRadius.circular(16),
                        onTap: () => _open(const ParkedScreen()),
                        child: Padding(
                          padding: const EdgeInsets.fromLTRB(14, 10, 10, 10),
                          child: Row(children: [
                            Container(
                              width: 40,
                              height: 40,
                              decoration: BoxDecoration(color: sprintBlue.withValues(alpha: 0.13), shape: BoxShape.circle),
                              child: const Icon(Icons.pause_rounded, color: sprintBlue, size: 22),
                            ),
                            const SizedBox(width: 14),
                            Expanded(
                              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                                const Text('Parked tasks', style: TextStyle(fontSize: 16.5, fontWeight: FontWeight.w600)),
                                Text(
                                  sprint.parked.isEmpty
                                      ? 'Nothing paused'
                                      : '${sprint.parked.length} paused task${sprint.parked.length == 1 ? '' : 's'} waiting',
                                  style: TextStyle(fontSize: 14, color: grey),
                                ),
                              ]),
                            ),
                            Icon(Icons.chevron_right_rounded, color: grey),
                          ]),
                        ),
                      ),
                    ),
                  ),

                  // ---- yesterday's unanswered ----
                  if (carryDay != null && carryCount > 0)
                    Container(
                      margin: const EdgeInsets.fromLTRB(16, 10, 16, 0),
                      padding: const EdgeInsets.fromLTRB(16, 12, 12, 12),
                      decoration: BoxDecoration(
                        color: light ? const Color(0xFFFFF4E5) : const Color(0xFF3A2A16),
                        borderRadius: BorderRadius.circular(16),
                      ),
                      child: Row(children: [
                        Expanded(
                          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                            Text(
                              '$carryCount task${carryCount == 1 ? '' : 's'} not updated on ${fmtDay(DateTime.parse(carryDay))}',
                              style: const TextStyle(fontSize: 15.5, fontWeight: FontWeight.w600),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              sprint.tasksFor(carryDay).where((t) => t.status == TaskStatus.open).map((t) => t.text).join(' · '),
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(fontSize: 14, color: grey),
                            ),
                            TextButton(
                              style: TextButton.styleFrom(padding: EdgeInsets.zero, minimumSize: const Size(0, 36)),
                              onPressed: () => _open(ReviewScreen(date: carryDay)),
                              child: const Text('Update that day instead'),
                            ),
                          ]),
                        ),
                        const SizedBox(width: 8),
                        FilledButton(
                          style: FilledButton.styleFrom(minimumSize: const Size(0, 44), padding: const EdgeInsets.symmetric(horizontal: 16)),
                          onPressed: () async {
                            await sprint.carryToToday(carryDay);
                            _toast('Added to today');
                          },
                          child: const Text('Add to today', style: TextStyle(fontSize: 15)),
                        ),
                      ]),
                    ),

                  ListHeader(isToday ? 'My tasks for today' : 'Tasks for ${fmtDay(day)}'),
                  if (list.isEmpty)
                    Padding(
                      padding: const EdgeInsets.fromLTRB(32, 28, 32, 8),
                      child: Column(children: [
                        Icon(Icons.checklist_rounded, size: 56, color: grey.withValues(alpha: 0.5)),
                        const SizedBox(height: 10),
                        Text(
                          isPast ? 'Nothing was planned for this day.' : 'No tasks yet. Type below to add your first one.',
                          textAlign: TextAlign.center,
                          style: TextStyle(fontSize: 16, color: grey),
                        ),
                      ]),
                    ),
                  for (final t in list)
                    _TaskRow(
                      task: t,
                      onToggle: () => sprint.toggleDone(t.id),
                      onLongPress: () => _taskMenu(t),
                    ),
                  if (list.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.fromLTRB(24, 14, 24, 0),
                      child: Text(
                        'Tap the circle when a task is done. Press and hold a task to change, pause or delete it.',
                        textAlign: TextAlign.center,
                        style: TextStyle(fontSize: 13.5, color: grey),
                      ),
                    ),
                ],
              ),
            ),
            if (!isPast) SprintComposer(controller: input, focus: focus, hint: isToday ? 'Add a task for today…' : 'Add a task for ${fmtDay(day)}…', onSend: _add),
          ]),
        );
      },
    );
  }

  bool _eveningPassed() {
    final n = DateTime.now();
    return n.hour * 60 + n.minute >= sprint.eveningMin;
  }
}

class _ProgressCard extends StatelessWidget {
  final int done;
  final int total;
  final String? footer;
  final String? action;
  final VoidCallback onAction;
  const _ProgressCard({required this.done, required this.total, this.footer, this.action, required this.onAction});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final grey = theme.colorScheme.onSurfaceVariant;
    final pct = total == 0 ? 0.0 : done / total;
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 10, 16, 0),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: theme.brightness == Brightness.light ? const Color(0xFFF0F2F5) : const Color(0xFF1F2C34),
        borderRadius: BorderRadius.circular(18),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Expanded(child: Text('$done of $total done', style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w600))),
          Text('${(pct * 100).round()}%', style: TextStyle(fontSize: 14, color: grey)),
        ]),
        const SizedBox(height: 10),
        ClipRRect(
          borderRadius: BorderRadius.circular(4),
          child: LinearProgressIndicator(
            value: pct,
            minHeight: 8,
            color: AppColors.accent,
            backgroundColor: grey.withValues(alpha: 0.25),
          ),
        ),
        if (footer != null) ...[
          const SizedBox(height: 10),
          Row(children: [
            Icon(Icons.notifications_none_rounded, size: 18, color: grey),
            const SizedBox(width: 6),
            Expanded(child: Text(footer!, style: TextStyle(fontSize: 14, color: grey))),
          ]),
        ],
        if (action != null) ...[
          const SizedBox(height: 6),
          TextButton.icon(
            style: TextButton.styleFrom(padding: EdgeInsets.zero, minimumSize: const Size(0, 40)),
            onPressed: onAction,
            icon: const Icon(Icons.fact_check_outlined, size: 20),
            label: Text(action!),
          ),
        ],
      ]),
    );
  }
}

class _TaskRow extends StatelessWidget {
  final SprintTask task;
  final VoidCallback onToggle;
  final VoidCallback onLongPress;
  const _TaskRow({required this.task, required this.onToggle, required this.onLongPress});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final grey = theme.colorScheme.onSurfaceVariant;
    final t = task;
    final done = t.status == TaskStatus.done;
    final (String? label, Color labelColor) = switch (t.status) {
      TaskStatus.notDone => ('Not done', notDoneColor),
      TaskStatus.paused => ('Paused – in Parked tasks', sprintBlue),
      _ => (t.from, const Color(0xFFC2410C)),
    };
    return InkWell(
      onLongPress: onLongPress,
      onTap: onLongPress,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(8, 2, 16, 2),
        child: Row(children: [
          Semantics(
            button: true,
            checked: done,
            label: done ? 'Mark not done' : 'Mark done',
            child: InkResponse(
              onTap: onToggle,
              radius: 26,
              child: SizedBox(
                width: 52,
                height: 52,
                child: Center(
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 150),
                    width: 28,
                    height: 28,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: done ? AppColors.accent : Colors.transparent,
                      border: Border.all(color: done ? AppColors.accent : grey, width: 2),
                    ),
                    child: done ? const Icon(Icons.check_rounded, size: 18, color: Colors.white) : null,
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Container(
              padding: const EdgeInsets.symmetric(vertical: 12),
              decoration: BoxDecoration(border: Border(bottom: BorderSide(color: theme.colorScheme.outlineVariant))),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(
                  t.text,
                  style: TextStyle(
                    fontSize: 17,
                    color: done || t.status == TaskStatus.paused ? grey : theme.colorScheme.onSurface,
                    decoration: done ? TextDecoration.lineThrough : null,
                  ),
                ),
                if (label != null) ...[
                  const SizedBox(height: 2),
                  Text(label, style: TextStyle(fontSize: 13.5, color: labelColor, fontWeight: FontWeight.w500)),
                ],
              ]),
            ),
          ),
        ]),
      ),
    );
  }
}

/// The message-style input at the bottom.
class SprintComposer extends StatelessWidget {
  final TextEditingController controller;
  final FocusNode? focus;
  final String hint;
  final VoidCallback onSend;
  final String sendLabel;
  const SprintComposer({super.key, required this.controller, this.focus, required this.hint, required this.onSend, this.sendLabel = 'Add task'});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final light = theme.brightness == Brightness.light;
    return Container(
      color: light ? const Color(0xFFF0F2F5) : const Color(0xFF1F2C34),
      padding: const EdgeInsets.fromLTRB(10, 8, 10, 8),
      child: SafeArea(
        top: false,
        child: Row(children: [
          Expanded(
            child: TextField(
              controller: controller,
              focusNode: focus,
              textCapitalization: TextCapitalization.sentences,
              textInputAction: TextInputAction.send,
              onSubmitted: (_) {
                onSend();
                focus?.requestFocus();
              },
              style: const TextStyle(fontSize: 16.5),
              decoration: InputDecoration(
                hintText: hint,
                filled: true,
                fillColor: light ? Colors.white : AppColors.darkBar,
                contentPadding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(28), borderSide: BorderSide.none),
                enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(28), borderSide: BorderSide.none),
                focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(28), borderSide: BorderSide.none),
              ),
            ),
          ),
          const SizedBox(width: 8),
          SizedBox(
            width: 50,
            height: 50,
            child: IconButton.filled(
              tooltip: sendLabel,
              style: IconButton.styleFrom(backgroundColor: AppColors.accent, foregroundColor: Colors.white),
              onPressed: onSend,
              icon: const Icon(Icons.add_rounded, size: 28),
            ),
          ),
        ]),
      ),
    );
  }
}

/// Small dialog to edit a line of text. Returns null when cancelled.
Future<String?> editTextDialog(BuildContext context, {required String title, required String initial}) {
  final ctrl = TextEditingController(text: initial);
  return showDialog<String>(
    context: context,
    builder: (c) => AlertDialog(
      title: Text(title),
      content: TextField(
        controller: ctrl,
        autofocus: true,
        textCapitalization: TextCapitalization.sentences,
        style: const TextStyle(fontSize: 17),
        onSubmitted: (v) => Navigator.pop(c, v),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(c), child: const Text('Cancel')),
        TextButton(onPressed: () => Navigator.pop(c, ctrl.text), child: const Text('Save')),
      ],
    ),
  );
}

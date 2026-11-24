import 'package:intl/intl.dart';
import 'package:material_ui/material_ui.dart';

import '../format.dart' show fmtDay, fmtMinutesOfDay;
import '../main.dart' show AppColors;
import '../models.dart' show isoDate, dateOnly;
import '../widgets.dart';
import 'achievements_view.dart';
import 'goals_view.dart';
import 'insights_view.dart';
import 'parked_screen.dart';
import 'review_screen.dart';
import 'sprint_history_screen.dart';
import 'sprint_settings_screen.dart';
import 'sprint_state.dart';

const sprintBlue = Color(0xFF3E63DD);
const notDoneColor = Color(0xFFC2410C);
const leaveColor = Color(0xFF8E4EC6);

/// The "Daily Sprint" tab: Today · Insights · Parked · History across the top.
class SprintScreen extends StatelessWidget {
  const SprintScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final sprint = SprintState.instance;
    return DefaultTabController(
      length: 6,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Daily Sprint'),
          actions: [
            IconButton(
              tooltip: 'Daily Sprint settings',
              onPressed: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const SprintSettingsScreen())),
              icon: const Icon(Icons.tune_rounded),
            ),
          ],
          bottom: TabBar(
            isScrollable: true,
            tabAlignment: TabAlignment.start,
            labelPadding: const EdgeInsets.symmetric(horizontal: 14),
            labelStyle: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w700, letterSpacing: 0.2),
            unselectedLabelStyle: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w500, letterSpacing: 0.2),
            indicatorWeight: 3,
            tabs: [
              const Tab(height: 42, text: 'TODAY'),
              const Tab(height: 42, text: 'GOALS'),
              const Tab(height: 42, text: 'ACHIEVEMENTS'),
              const Tab(height: 42, text: 'INSIGHTS'),
              Tab(
                height: 42,
                child: ListenableBuilder(
                  listenable: sprint,
                  builder: (_, _) => Row(mainAxisSize: MainAxisSize.min, children: [
                    const Text('PARKED'),
                    if (sprint.parked.isNotEmpty) ...[
                      const SizedBox(width: 5),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                        decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(9)),
                        child: Text('${sprint.parked.length}',
                            style: const TextStyle(fontSize: 11, color: AppColors.green, fontWeight: FontWeight.w700)),
                      ),
                    ],
                  ]),
                ),
              ),
              const Tab(height: 42, text: 'HISTORY'),
            ],
          ),
        ),
        body: const TabBarView(children: [
          TodayView(),
          GoalsView(),
          AchievementsView(),
          InsightsView(),
          ParkedView(),
          SprintHistoryView(),
        ]),
      ),
    );
  }
}

/// One day's plan, with a message-style box to add tasks.
class TodayView extends StatefulWidget {
  const TodayView({super.key});

  @override
  State<TodayView> createState() => _TodayViewState();
}

class _TodayViewState extends State<TodayView> with AutomaticKeepAliveClientMixin {
  final sprint = SprintState.instance;
  final input = TextEditingController();
  final focus = FocusNode();
  late DateTime day = dateOnly(DateTime.now());

  @override
  bool get wantKeepAlive => true;

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
            padding: const EdgeInsets.fromLTRB(24, 0, 24, 4),
            child: Text(t.text, style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w600)),
          ),
          OptionRow(icon: Icons.edit_outlined, title: 'Change text', onTap: () => Navigator.pop(c, 'edit')),
          if (t.status == TaskStatus.done)
            OptionRow(icon: Icons.emoji_events_outlined, title: 'Add to achievements', onTap: () => Navigator.pop(c, 'win')),
          if (t.status != TaskStatus.paused)
            OptionRow(icon: Icons.pause_rounded, title: 'Pause – move to Parked', onTap: () => Navigator.pop(c, 'pause')),
          OptionRow(icon: Icons.delete_outline_rounded, title: 'Delete', color: AppColors.red, onTap: () => Navigator.pop(c, 'delete')),
          const SizedBox(height: 6),
        ]),
      ),
    );
    if (!mounted) return;
    switch (choice) {
      case 'edit':
        final text = await editTextDialog(context, title: 'Change task', initial: t.text);
        if (text != null) await sprint.rename(t.id, text);
      case 'win':
        await showAchievementSheet(context, title: t.text, date: t.date);
      case 'pause':
        await sprint.pause(t.id);
        _toast('Paused – see the Parked tab');
      case 'delete':
        await sprint.delete(t.id);
        _toast('Task deleted');
    }
  }

  void _toast(String text) {
    final m = ScaffoldMessenger.of(context);
    m.clearSnackBars();
    m.showSnackBar(SnackBar(content: Text(text)));
  }

  String _dayTitle() {
    final rel = fmtDay(day);
    return rel == 'Today' || rel == 'Tomorrow' || rel == 'Yesterday' ? rel : DateFormat('EEEE').format(day);
  }

  /// "Mark as leave": full day, half day or public holiday, with an optional note.
  Future<void> _markLeave() async {
    var type = LeaveType.leave;
    final note = TextEditingController();
    final open = sprint.tasksFor(dayKey).where((t) => t.status == TaskStatus.open).length;
    final ok = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      builder: (c) => StatefulBuilder(
        builder: (c, set) => Padding(
          padding: EdgeInsets.only(bottom: MediaQuery.of(c).viewInsets.bottom),
          child: SafeArea(
            child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(24, 0, 24, 4),
                child: Text('Mark ${DateFormat('EEE, d MMM').format(day)} as',
                    style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w600)),
              ),
              for (final (value, label) in const [
                (LeaveType.leave, 'Leave – full day'),
                (LeaveType.half, 'Half-day leave'),
                (LeaveType.holiday, 'Public holiday'),
              ])
                RadioRow(label: label, selected: type == value, onTap: () => set(() => type = value)),
              Padding(
                padding: const EdgeInsets.fromLTRB(24, 4, 24, 0),
                child: TextField(
                  controller: note,
                  textCapitalization: TextCapitalization.sentences,
                  style: const TextStyle(fontSize: 15),
                  decoration: const InputDecoration(isDense: true, hintText: 'Note (optional), e.g. Sick, Diwali'),
                ),
              ),
              if (open > 0 && type != LeaveType.half)
                Padding(
                  padding: const EdgeInsets.fromLTRB(24, 10, 24, 0),
                  child: Text(
                    '$open open task${open == 1 ? '' : 's'} will move to the next work day.',
                    style: TextStyle(fontSize: 13, color: Theme.of(c).colorScheme.onSurfaceVariant),
                  ),
                ),
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 14, 20, 12),
                child: SizedBox(
                  width: double.infinity,
                  child: FilledButton(onPressed: () => Navigator.pop(c, true), child: const Text('Save')),
                ),
              ),
            ]),
          ),
        ),
      ),
    );
    if (ok != true || !mounted) return;
    final moved = await sprint.setLeave(dayKey, type, note: note.text);
    _toast(moved > 0 ? 'Saved. $moved task${moved == 1 ? '' : 's'} moved to the next work day.' : 'Saved');
  }

  bool _eveningPassed() {
    final n = DateTime.now();
    return n.hour * 60 + n.minute >= sprint.eveningMin;
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final theme = Theme.of(context);
    final grey = theme.colorScheme.onSurfaceVariant;
    final light = theme.brightness == Brightness.light;
    final green = light ? AppColors.green : AppColors.accent;
    return ListenableBuilder(
      listenable: sprint,
      builder: (context, _) {
        final list = sprint.tasksFor(dayKey);
        final done = list.where((t) => t.status == TaskStatus.done).length;
        final open = list.where((t) => t.status == TaskStatus.open).length;
        final carryDay = isToday ? sprint.unansweredDay : null;
        final carryTasks = carryDay == null ? const <SprintTask>[] : sprint.tasksFor(carryDay).where((t) => t.status == TaskStatus.open).toList();
        final workday = sprint.workdays.contains(day.weekday);
        final leave = sprint.leaveOn(dayKey);
        final showHint = isToday && sprint.eveningOn && workday && open > 0 && !_eveningPassed() && leave?.fullDayOff != true;

        return Column(children: [
          Expanded(
            child: ListView(
              padding: const EdgeInsets.only(bottom: 12),
              children: [
                // ---- day switcher: one compact line ----
                Padding(
                  padding: const EdgeInsets.fromLTRB(4, 4, 4, 0),
                  child: Row(children: [
                    IconButton(
                      tooltip: 'Previous day',
                      visualDensity: VisualDensity.compact,
                      onPressed: () => setState(() => day = day.subtract(const Duration(days: 1))),
                      icon: const Icon(Icons.chevron_left_rounded),
                    ),
                    Expanded(
                      child: InkWell(
                        borderRadius: BorderRadius.circular(10),
                        onTap: isToday ? null : () => setState(() => day = dateOnly(DateTime.now())),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(vertical: 6),
                          child: Text.rich(
                            TextSpan(children: [
                              TextSpan(text: _dayTitle(), style: const TextStyle(fontWeight: FontWeight.w700)),
                              TextSpan(text: '  ${DateFormat('d MMM').format(day)}', style: TextStyle(color: grey)),
                              if (!isToday) TextSpan(text: '  · back to today', style: TextStyle(color: green, fontSize: 12.5)),
                            ]),
                            textAlign: TextAlign.center,
                            style: const TextStyle(fontSize: 15),
                          ),
                        ),
                      ),
                    ),
                    IconButton(
                      tooltip: 'Next day',
                      visualDensity: VisualDensity.compact,
                      onPressed: () => setState(() => day = day.add(const Duration(days: 1))),
                      icon: const Icon(Icons.chevron_right_rounded),
                    ),
                  ]),
                ),

                // ---- leave ----
                if (leave != null)
                  Container(
                    margin: const EdgeInsets.fromLTRB(16, 2, 16, 6),
                    padding: const EdgeInsets.fromLTRB(14, 8, 6, 8),
                    decoration: BoxDecoration(
                      color: leaveColor.withValues(alpha: light ? 0.12 : 0.22),
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: Row(children: [
                      Icon(leave.type == LeaveType.holiday ? Icons.celebration_outlined : Icons.beach_access_outlined,
                          size: 20, color: leaveColor),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                          Text(leave.label, style: const TextStyle(fontSize: 14.5, fontWeight: FontWeight.w600)),
                          Text(leave.note ?? (leave.fullDayOff ? 'No check-in or reminders for this day' : 'Check-in still happens'),
                              style: TextStyle(fontSize: 12.5, color: grey)),
                        ]),
                      ),
                      TextButton(
                        style: TextButton.styleFrom(visualDensity: VisualDensity.compact),
                        onPressed: () async {
                          await sprint.clearLeave(dayKey);
                          _toast('Leave removed');
                        },
                        child: const Text('Undo'),
                      ),
                    ]),
                  )
                else
                  Center(
                    child: TextButton.icon(
                      style: TextButton.styleFrom(
                        visualDensity: VisualDensity.compact,
                        foregroundColor: grey,
                        textStyle: TextStyle(fontFamily: theme.textTheme.bodyMedium?.fontFamily, fontSize: 13, fontWeight: FontWeight.w500),
                      ),
                      onPressed: () => _markLeave(),
                      icon: const Icon(Icons.beach_access_outlined, size: 17),
                      label: Text(isToday ? 'Mark today as leave' : 'Mark this day as leave'),
                    ),
                  ),

                // ---- progress: one slim card ----
                if (list.isNotEmpty)
                  Container(
                    margin: const EdgeInsets.fromLTRB(16, 2, 16, 0),
                    padding: const EdgeInsets.fromLTRB(14, 10, 6, 10),
                    decoration: BoxDecoration(
                      color: light ? const Color(0xFFF5F7F8) : const Color(0xFF1A262D),
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Row(children: [
                        Text('$done of ${list.length} done', style: const TextStyle(fontSize: 14.5, fontWeight: FontWeight.w600)),
                        const SizedBox(width: 8),
                        Text('${(done * 100 / list.length).round()}%', style: TextStyle(fontSize: 13, color: grey)),
                        const Spacer(),
                        if (isPast || isToday)
                          TextButton(
                            style: TextButton.styleFrom(
                              visualDensity: VisualDensity.compact,
                              textStyle: TextStyle(fontFamily: theme.textTheme.bodyMedium?.fontFamily, fontSize: 13.5, fontWeight: FontWeight.w600),
                            ),
                            onPressed: () => _open(ReviewScreen(date: dayKey)),
                            child: Text(open > 0 ? 'Update ($open)' : 'Change status'),
                          ),
                      ]),
                      Padding(
                        padding: const EdgeInsets.only(right: 8, top: 2),
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(3),
                          child: LinearProgressIndicator(
                            value: done / list.length,
                            minHeight: 6,
                            color: AppColors.accent,
                            backgroundColor: grey.withValues(alpha: 0.2),
                          ),
                        ),
                      ),
                      if (showHint)
                        Padding(
                          padding: const EdgeInsets.only(top: 8),
                          child: Row(children: [
                            Icon(Icons.notifications_none_rounded, size: 15, color: grey),
                            const SizedBox(width: 5),
                            Text('Check-in at ${fmtMinutesOfDay(context, sprint.eveningMin)}',
                                style: TextStyle(fontSize: 12.5, color: grey)),
                          ]),
                        ),
                    ]),
                  ),

                // ---- unanswered earlier day ----
                if (carryTasks.isNotEmpty)
                  Container(
                    margin: const EdgeInsets.fromLTRB(16, 8, 16, 0),
                    padding: const EdgeInsets.fromLTRB(14, 10, 8, 8),
                    decoration: BoxDecoration(
                      color: light ? const Color(0xFFFFF4E5) : const Color(0xFF3A2A16),
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text(
                        '${carryTasks.length} task${carryTasks.length == 1 ? '' : 's'} not updated on ${fmtDay(DateTime.parse(carryDay!))}',
                        style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
                      ),
                      const SizedBox(height: 2),
                      Text(carryTasks.map((t) => t.text).join(' · '),
                          maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 13, color: grey)),
                      Row(mainAxisAlignment: MainAxisAlignment.end, children: [
                        TextButton(
                          style: TextButton.styleFrom(visualDensity: VisualDensity.compact, textStyle: const TextStyle(fontSize: 13.5)),
                          onPressed: () => _open(ReviewScreen(date: carryDay)),
                          child: const Text('Update that day'),
                        ),
                        const SizedBox(width: 4),
                        FilledButton(
                          style: FilledButton.styleFrom(
                            minimumSize: const Size(0, 36),
                            padding: const EdgeInsets.symmetric(horizontal: 14),
                            textStyle: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w600),
                          ),
                          onPressed: () async {
                            await sprint.carryToToday(carryDay);
                            _toast('Added to today');
                          },
                          child: const Text('Add to today'),
                        ),
                      ]),
                    ]),
                  ),

                if (list.isEmpty)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(32, 48, 32, 8),
                    child: Column(children: [
                      Icon(Icons.checklist_rounded, size: 48, color: grey.withValues(alpha: 0.45)),
                      const SizedBox(height: 10),
                      Text(
                        isPast ? 'Nothing was planned for this day.' : 'Nothing planned yet.\nType below to add your first task.',
                        textAlign: TextAlign.center,
                        style: TextStyle(fontSize: 14.5, color: grey, height: 1.4),
                      ),
                    ]),
                  )
                else ...[
                  const SizedBox(height: 6),
                  for (final t in list)
                    TaskRow(task: t, onToggle: () => sprint.toggleDone(t.id), onMenu: () => _taskMenu(t)),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(24, 12, 24, 0),
                    child: Text('Tap the circle when done · tap a task for more',
                        textAlign: TextAlign.center, style: TextStyle(fontSize: 12, color: grey)),
                  ),
                ],
              ],
            ),
          ),
          if (!isPast && leave?.fullDayOff != true)
            SprintComposer(
              controller: input,
              focus: focus,
              hint: isToday ? 'Add a task for today' : 'Add a task for ${fmtDay(day)}',
              onSend: _add,
            ),
        ]);
      },
    );
  }
}

class TaskRow extends StatelessWidget {
  final SprintTask task;
  final VoidCallback onToggle;
  final VoidCallback onMenu;
  const TaskRow({super.key, required this.task, required this.onToggle, required this.onMenu});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final grey = theme.colorScheme.onSurfaceVariant;
    final t = task;
    final done = t.status == TaskStatus.done;
    final (String? label, Color labelColor) = switch (t.status) {
      TaskStatus.notDone => ('Not done', notDoneColor),
      TaskStatus.paused => ('Paused · in Parked', sprintBlue),
      _ => (t.from, notDoneColor),
    };
    return InkWell(
      onTap: onMenu,
      onLongPress: onMenu,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(6, 0, 16, 0),
        child: Row(children: [
          Semantics(
            button: true,
            checked: done,
            label: done ? 'Mark not done' : 'Mark done',
            child: InkResponse(
              onTap: onToggle,
              radius: 22,
              child: SizedBox(
                width: 44,
                height: 44,
                child: Center(
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 150),
                    width: 22,
                    height: 22,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: done ? AppColors.accent : Colors.transparent,
                      border: Border.all(color: done ? AppColors.accent : grey.withValues(alpha: 0.8), width: 1.8),
                    ),
                    child: done ? const Icon(Icons.check_rounded, size: 15, color: Colors.white) : null,
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(width: 6),
          Expanded(
            child: Container(
              padding: const EdgeInsets.symmetric(vertical: 11),
              decoration: BoxDecoration(border: Border(bottom: BorderSide(color: theme.colorScheme.outlineVariant))),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(
                  t.text,
                  style: TextStyle(
                    fontSize: 15,
                    color: done || t.status == TaskStatus.paused ? grey : theme.colorScheme.onSurface,
                    decoration: done ? TextDecoration.lineThrough : null,
                  ),
                ),
                if (label != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 1),
                    child: Text(label, style: TextStyle(fontSize: 12, color: labelColor, fontWeight: FontWeight.w500)),
                  ),
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
    final border = OutlineInputBorder(borderRadius: BorderRadius.circular(22), borderSide: BorderSide.none);
    return Container(
      color: light ? const Color(0xFFF0F2F5) : const Color(0xFF1F2C34),
      padding: const EdgeInsets.fromLTRB(8, 6, 8, 6),
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
              style: const TextStyle(fontSize: 15),
              decoration: InputDecoration(
                hintText: hint,
                isDense: true,
                filled: true,
                fillColor: light ? Colors.white : AppColors.darkBar,
                contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 11),
                border: border,
                enabledBorder: border,
                focusedBorder: border,
              ),
            ),
          ),
          const SizedBox(width: 6),
          SizedBox(
            width: 42,
            height: 42,
            child: IconButton.filled(
              tooltip: sendLabel,
              padding: EdgeInsets.zero,
              style: IconButton.styleFrom(backgroundColor: AppColors.accent, foregroundColor: Colors.white),
              onPressed: onSend,
              icon: const Icon(Icons.add_rounded, size: 24),
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
      title: Text(title, style: const TextStyle(fontSize: 18)),
      content: TextField(
        controller: ctrl,
        autofocus: true,
        textCapitalization: TextCapitalization.sentences,
        style: const TextStyle(fontSize: 15.5),
        onSubmitted: (v) => Navigator.pop(c, v),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(c), child: const Text('Cancel')),
        TextButton(onPressed: () => Navigator.pop(c, ctrl.text), child: const Text('Save')),
      ],
    ),
  );
}

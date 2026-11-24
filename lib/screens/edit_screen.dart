import 'dart:async';

import 'package:intl/intl.dart';
import 'package:material_ui/material_ui.dart';

import '../format.dart';
import '../main.dart' show AppColors;
import '../models.dart';
import '../native.dart';
import '../state.dart';
import '../widgets.dart';
import 'home_screen.dart' show confirmDelete;
import 'sound_picker_screen.dart';

const bundledSoundNames = {
  'gentle_chime': 'Gentle Chime',
  'morning_marimba': 'Morning Marimba',
  'soft_bells': 'Soft Bells',
  'ding_dong': 'Ding Dong',
  'water_drop': 'Water Drop',
  'lullaby': 'Lullaby',
  'rising_alert': 'Rising Alert',
  'classic_beep': 'Classic Beep',
  'digital_alarm': 'Digital Alarm',
  'heartbeat_pulse': 'Heartbeat Pulse',
};

const _repeatChoices = [
  ('once', 'Does not repeat'),
  ('daily', 'Every day'),
  ('weekly', 'On some days of the week'),
  ('monthly', 'Every month'),
  ('yearly', 'Every year'),
  ('hourly', 'Many times a day'),
];

class EditScreen extends StatefulWidget {
  final Reminder? reminder;
  final Template? template;
  const EditScreen({super.key, this.reminder, this.template});

  @override
  State<EditScreen> createState() => _EditScreenState();
}

class _EditScreenState extends State<EditScreen> {
  final state = AppState.instance;
  late Reminder draft;
  late final TextEditingController titleCtrl;
  late final TextEditingController notesCtrl;
  Template? selectedTemplate;
  List<DateTime> preview = [];
  Timer? _previewDebounce;
  bool saving = false;

  bool get isNew => widget.reminder == null;

  @override
  void initState() {
    super.initState();
    final nextHour = DateTime.now().add(const Duration(hours: 1));
    var r = widget.reminder ??
        Reminder(
          startDate: dateOnly(nextHour),
          hour: nextHour.hour,
          minute: 0,
          soundUri: state.setting<String?>('defaultSoundUri', null),
          soundName: state.setting<String?>('defaultSoundName', null),
          vibrate: state.setting('vibrate', true),
          snoozeMinutes: (state.settings['snoozeMinutes'] as num?)?.toInt() ?? 10,
        );
    // Opening a finished one-time reminder usually means "use it again".
    if (!isNew && !r.enabled && r.repeat.type == 'once' && r.lastFired != null) r = r.copyWith(enabled: true);
    draft = r;
    titleCtrl = TextEditingController(text: draft.title);
    notesCtrl = TextEditingController(text: draft.notes);
    if (widget.template != null) _applyTemplate(widget.template!);
    _refreshPreview();
  }

  @override
  void dispose() {
    _previewDebounce?.cancel();
    titleCtrl.dispose();
    notesCtrl.dispose();
    super.dispose();
  }

  void _applyTemplate(Template t) {
    final now = DateTime.now();
    var date = dateOnly(now);
    // One-time templates default to tomorrow; others start today unless that time has passed.
    // ("Many times a day" stays on today: the next slot later today is used.)
    if (t.repeat.type == 'once' ||
        (t.repeat.type != 'hourly' && DateTime(now.year, now.month, now.day, t.hour, t.minute).isBefore(now))) {
      date = date.add(const Duration(days: 1));
    }
    selectedTemplate = t;
    titleCtrl.text = t.title;
    notesCtrl.text = t.notes;
    draft = draft.copyWith(
      title: t.title,
      notes: t.notes,
      category: t.category,
      hour: t.hour,
      minute: t.minute,
      startDate: date,
      repeat: t.repeat,
      soundUri: t.soundKey != null ? 'remindly-tune://${t.soundKey}' : null,
      soundName: t.soundKey != null ? bundledSoundNames[t.soundKey] : null,
    );
  }

  void _update(Reminder r) {
    setState(() => draft = r);
    _refreshPreview();
  }

  void _refreshPreview() {
    _previewDebounce?.cancel();
    _previewDebounce = Timer(const Duration(milliseconds: 250), () async {
      try {
        final p = await Native.preview(draft.copyWith(enabled: true), count: 3);
        if (mounted) setState(() => preview = p);
      } catch (_) {}
    });
  }

  // ---------------- pickers ----------------

  Future<void> _pickDate() async {
    final now = DateTime.now();
    final first = DateTime(now.year - 5);
    final picked = await showDatePicker(
      context: context,
      initialDate: draft.startDate.isBefore(first) ? now : draft.startDate,
      firstDate: first,
      lastDate: DateTime(now.year + 30),
      helpText: 'Choose the date',
    );
    if (picked != null) _update(draft.copyWith(startDate: picked));
  }

  Future<void> _pickTime({bool untilTime = false}) async {
    final m = untilTime ? (draft.repeat.windowEnd ?? 22 * 60) : draft.hour * 60 + draft.minute;
    final picked = await showTimePicker(
      context: context,
      initialTime: TimeOfDay(hour: m ~/ 60, minute: m % 60),
      helpText: untilTime ? 'Last reminder of the day' : 'Remind me at',
    );
    if (picked == null) return;
    if (untilTime) {
      _update(draft.copyWith(repeat: draft.repeat.copyWith(windowEnd: () => picked.hour * 60 + picked.minute)));
    } else {
      _update(draft.copyWith(hour: picked.hour, minute: picked.minute));
    }
  }

  Future<void> _pickSound() async {
    final picked = await Navigator.of(context).push<SoundOption>(
      MaterialPageRoute(builder: (_) => SoundPickerScreen(selectedUri: draft.soundUri)),
    );
    if (picked != null) _update(draft.copyWith(soundUri: picked.uri, soundName: picked.title));
  }

  Future<void> _pickSnooze() async {
    final v = await chooseOne<int>(
      context,
      title: 'If I tap "Remind me later", ring again after',
      options: const [(5, '5 minutes'), (10, '10 minutes'), (15, '15 minutes'), (30, '30 minutes'), (60, '1 hour')],
      current: draft.snoozeMinutes,
    );
    if (v != null) _update(draft.copyWith(snoozeMinutes: v));
  }

  Future<void> _pickIcon() async {
    final key = await showModalBottomSheet<String>(
      context: context,
      builder: (c) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Padding(
              padding: EdgeInsets.fromLTRB(8, 0, 8, 16),
              child: Text('Choose a picture', style: TextStyle(fontSize: 17.5, fontWeight: FontWeight.w600)),
            ),
            GridView.count(
              crossAxisCount: 4,
              shrinkWrap: true,
              mainAxisSpacing: 8,
              childAspectRatio: 0.9,
              children: [
                for (final cat in categories)
                  InkWell(
                    borderRadius: BorderRadius.circular(16),
                    onTap: () => Navigator.pop(c, cat.key),
                    child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                      Container(
                        width: 58,
                        height: 58,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: cat.key == draft.category ? cat.color : cat.color.withValues(alpha: 0.15),
                        ),
                        child: Icon(cat.icon, size: 30, color: cat.key == draft.category ? Colors.white : cat.color),
                      ),
                      const SizedBox(height: 6),
                      Text(cat.label, style: const TextStyle(fontSize: 13)),
                    ]),
                  ),
              ],
            ),
          ]),
        ),
      ),
    );
    if (key != null) _update(draft.copyWith(category: key));
  }

  /// The one place where repeating is set up, in plain words.
  Future<void> _pickRepeat() async {
    var rule = draft.repeat;
    final result = await showModalBottomSheet<RepeatRule>(
      context: context,
      isScrollControlled: true,
      builder: (c) => StatefulBuilder(builder: (c, setSheet) {
        void set(RepeatRule r) => setSheet(() => rule = r);
        Widget chips(List<(int, String)> opts) => Container(
              alignment: Alignment.centerLeft,
              padding: const EdgeInsets.fromLTRB(70, 0, 20, 8),
              child: Wrap(spacing: 8, runSpacing: 8, children: [
                for (final (n, label) in opts)
                  ChoiceChip(
                    label: Text(label),
                    selected: rule.interval == n,
                    onSelected: (_) => set(rule.copyWith(interval: n)),
                  ),
              ]),
            );
        return ConstrainedBox(
          constraints: BoxConstraints(maxHeight: MediaQuery.of(c).size.height * 0.85),
          child: SafeArea(
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              const Padding(
                padding: EdgeInsets.fromLTRB(24, 0, 24, 8),
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: Text('Repeat', style: TextStyle(fontSize: 17.5, fontWeight: FontWeight.w600)),
                ),
              ),
              Flexible(
                child: SingleChildScrollView(
                  child: Column(mainAxisSize: MainAxisSize.min, children: [
                    for (final (type, label) in _repeatChoices) ...[
                      RadioRow(label: label, selected: rule.type == type, onTap: () => set(_switchType(rule, type))),
                      if (rule.type == type) ...switch (type) {
                        'daily' => [chips(const [(1, 'Every day'), (2, 'Every 2 days'), (3, 'Every 3 days')])],
                        'weekly' => [
                            Padding(
                              padding: const EdgeInsets.fromLTRB(70, 4, 24, 8),
                              child: DayPicker(
                                selected: rule.weekdays.toSet(),
                                onToggle: (d) {
                                  final s = rule.weekdays.toSet();
                                  if (!s.remove(d)) s.add(d);
                                  if (s.isNotEmpty) set(rule.copyWith(weekdays: s.toList()..sort()));
                                },
                              ),
                            ),
                            Container(
                              alignment: Alignment.centerLeft,
                              padding: const EdgeInsets.fromLTRB(70, 0, 20, 8),
                              child: Wrap(spacing: 8, children: [
                                ActionChip(label: const Text('Mon – Fri'), onPressed: () => set(rule.copyWith(weekdays: [1, 2, 3, 4, 5]))),
                                ActionChip(label: const Text('Sat & Sun'), onPressed: () => set(rule.copyWith(weekdays: [6, 7]))),
                              ]),
                            ),
                          ],
                        'monthly' => [
                            chips(const [(1, 'Every month'), (2, 'Every 2 months'), (3, 'Every 3 months'), (6, 'Every 6 months'), (12, 'Every 12 months')]),
                            Padding(
                              padding: const EdgeInsets.fromLTRB(70, 0, 20, 8),
                              child: Text('On the ${ordinal(draft.startDate.day)} of the month',
                                  style: TextStyle(fontSize: 13.5, color: Theme.of(c).colorScheme.onSurfaceVariant)),
                            ),
                          ],
                        'hourly' => [
                            Padding(
                              padding: const EdgeInsets.fromLTRB(70, 0, 20, 6),
                              child: Text('Remind me every',
                                  style: TextStyle(fontSize: 13.5, color: Theme.of(c).colorScheme.onSurfaceVariant)),
                            ),
                            chips(const [(30, '30 min'), (60, '1 hour'), (120, '2 hours'), (180, '3 hours'), (240, '4 hours')]),
                          ],
                        _ => const <Widget>[],
                      },
                    ],
                    if (rule.type != 'once') ...[
                      const Divider(),
                      OptionRow(
                        icon: Icons.event_busy_rounded,
                        title: 'Stop repeating',
                        value: rule.endDate == null ? 'Never' : 'After ${DateFormat('d MMM y').format(rule.endDate!)}',
                        trailing: rule.endDate == null
                            ? null
                            : IconButton(
                                tooltip: 'Never stop',
                                onPressed: () => set(rule.copyWith(endDate: () => null)),
                                icon: const Icon(Icons.close_rounded),
                              ),
                        onTap: () async {
                          final now = DateTime.now();
                          final d = await showDatePicker(
                            context: c,
                            initialDate: rule.endDate ?? draft.startDate.add(const Duration(days: 30)),
                            firstDate: DateTime(now.year - 5),
                            lastDate: DateTime(now.year + 30),
                            helpText: 'Stop repeating after',
                          );
                          if (d != null) set(rule.copyWith(endDate: () => d));
                        },
                      ),
                    ],
                  ]),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 8, 20, 12),
                child: SizedBox(
                  width: double.infinity,
                  child: FilledButton(onPressed: () => Navigator.pop(c, rule), child: const Text('Done')),
                ),
              ),
            ]),
          ),
        );
      }),
    );
    if (result != null) _update(draft.copyWith(repeat: result));
  }

  RepeatRule _switchType(RepeatRule r, String type) {
    switch (type) {
      case 'weekly':
        return r.copyWith(type: type, interval: 1, weekdays: r.weekdays.isEmpty ? [draft.startDate.weekday] : r.weekdays);
      case 'hourly':
        final start = draft.hour * 60 + draft.minute;
        return r.copyWith(type: type, interval: 120, windowEnd: () => start < 22 * 60 ? 22 * 60 : 23 * 60 + 59);
      case 'once':
        return r.copyWith(type: type, interval: 1, endDate: () => null);
      default:
        return r.copyWith(type: type, interval: 1);
    }
  }

  // ---------------- save / delete ----------------

  Future<void> _save() async {
    final title = titleCtrl.text.trim();
    final r = draft.copyWith(
      title: title.isEmpty ? categoryOf(draft.category).label : title,
      notes: notesCtrl.text.trim(),
      enabled: isNew ? true : draft.enabled,
    );
    if (r.enabled && r.repeat.type == 'once' && !r.startDateTime.isAfter(DateTime.now())) {
      _problem('This time has already passed. Please choose a later time.');
      return;
    }
    if (r.repeat.endDate != null && dateOnly(r.repeat.endDate!).isBefore(dateOnly(r.startDate))) {
      _problem('"Stop repeating" date is before the start date.');
      return;
    }
    setState(() => saving = true);
    final navigator = Navigator.of(context);
    final messenger = ScaffoldMessenger.of(context);
    try {
      final saved = await state.save(r);
      navigator.pop();
      final next = saved.nextAlert;
      messenger.clearSnackBars();
      messenger.showSnackBar(SnackBar(
        content: Text(next != null ? 'Saved ✓  It will ring ${fmtRelative(next)}.' : 'Saved ✓',
            style: const TextStyle(fontSize: 14.5)),
      ));
    } catch (e) {
      setState(() => saving = false);
      _problem('Could not save. Please try again.');
    }
  }

  void _problem(String text) => showDialog<void>(
        context: context,
        builder: (c) => AlertDialog(
          content: Text(text, style: const TextStyle(fontSize: 15)),
          actions: [TextButton(onPressed: () => Navigator.pop(c), child: const Text('OK'))],
        ),
      );

  Future<void> _delete() async {
    if (await confirmDelete(context, draft)) {
      await state.delete(draft.id);
      if (mounted) Navigator.of(context).pop();
    }
  }

  // ---------------- UI ----------------

  String _dateLabel(DateTime d) {
    final rel = fmtDay(d);
    final full = DateFormat('d MMM y').format(d);
    return rel == 'Today' || rel == 'Tomorrow' ? '$rel, $full' : DateFormat('EEEE, d MMM y').format(d);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final grey = theme.colorScheme.onSurfaceVariant;
    final rule = draft.repeat;
    final hourly = rule.type == 'hourly';
    final cat = categoryOf(draft.category);

    return Scaffold(
      appBar: AppBar(title: Text(isNew ? 'New reminder' : 'Change reminder')),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 12),
          child: FilledButton(
            onPressed: saving ? null : _save,
            child: const Text('Save'),
          ),
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.only(bottom: 24),
        children: [
          // Picture + name
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 4),
            child: Row(crossAxisAlignment: CrossAxisAlignment.center, children: [
              Semantics(
                button: true,
                label: 'Change picture',
                child: GestureDetector(
                  onTap: _pickIcon,
                  child: Stack(clipBehavior: Clip.none, children: [
                    Container(
                      width: 56,
                      height: 56,
                      decoration: BoxDecoration(color: cat.color.withValues(alpha: 0.15), shape: BoxShape.circle),
                      child: Icon(cat.icon, color: cat.color, size: 28),
                    ),
                    Positioned(
                      right: -2,
                      bottom: -2,
                      child: Container(
                        width: 22,
                        height: 22,
                        decoration: BoxDecoration(
                          color: AppColors.accent,
                          shape: BoxShape.circle,
                          border: Border.all(color: theme.colorScheme.surface, width: 2),
                        ),
                        child: const Icon(Icons.edit_rounded, color: Colors.white, size: 12),
                      ),
                    ),
                  ]),
                ),
              ),
              const SizedBox(width: 18),
              Expanded(
                child: TextField(
                  controller: titleCtrl,
                  textCapitalization: TextCapitalization.sentences,
                  style: const TextStyle(fontSize: 17.5),
                  decoration: const InputDecoration(labelText: 'What should I remind you?', hintText: 'e.g. Take BP tablet'),
                  onChanged: (v) => draft = draft.copyWith(title: v),
                ),
              ),
            ]),
          ),
          if (isNew) ...[
            const ListHeader('Or pick one'),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
              child: Wrap(spacing: 8, runSpacing: 8, children: [
                for (final t in templates)
                  ChoiceChip(
                    avatar: Icon(categoryOf(t.category).icon, color: categoryOf(t.category).color, size: 20),
                    showCheckmark: false,
                    label: Text(t.label),
                    selected: selectedTemplate == t,
                    onSelected: (_) {
                      setState(() => _applyTemplate(t));
                      _refreshPreview();
                    },
                  ),
              ]),
            ),
          ],

          const GroupGap(title: 'When'),
          OptionRow(
            icon: Icons.calendar_today_rounded,
            title: rule.type == 'once' ? 'Date' : 'Starting from',
            value: _dateLabel(draft.startDate),
            onTap: _pickDate,
          ),
          OptionRow(
            icon: Icons.access_time_rounded,
            title: hourly ? 'First reminder at' : 'Time',
            value: fmtMinutesOfDay(context, draft.hour * 60 + draft.minute),
            onTap: _pickTime,
          ),
          if (hourly)
            OptionRow(
              icon: Icons.bedtime_outlined,
              title: 'Last reminder at',
              value: fmtMinutesOfDay(context, rule.windowEnd ?? 23 * 60 + 59),
              onTap: () => _pickTime(untilTime: true),
            ),
          OptionRow(
            icon: Icons.repeat_rounded,
            title: 'Repeat',
            value: rule.type == 'once' ? 'Does not repeat' : repeatSummary(context, draft),
            onTap: _pickRepeat,
          ),
          if (preview.isNotEmpty)
            Padding(
              padding: const EdgeInsets.fromLTRB(70, 0, 20, 12),
              child: Text(
                rule.type == 'once'
                    ? 'Will ring ${fmtRelative(preview.first)}'
                    : 'Next: ${preview.map((d) => fmtWhen(context, d)).join(',  ')}',
                style: TextStyle(fontSize: 13, color: grey),
              ),
            ),

          const GroupGap(title: 'Alert'),
          OptionRow(
            icon: draft.soundOn ? Icons.volume_up_rounded : Icons.volume_off_rounded,
            title: 'Sound',
            value: draft.soundOn ? 'On' : 'Off – only the screen alert',
            trailing: Switch(value: draft.soundOn, onChanged: (v) => _update(draft.copyWith(soundOn: v))),
            onTap: () => _update(draft.copyWith(soundOn: !draft.soundOn)),
          ),
          if (draft.soundOn)
            OptionRow(icon: Icons.music_note_rounded, title: 'Tune', value: draft.soundName ?? 'Default', onTap: _pickSound),
          OptionRow(
            icon: Icons.vibration_rounded,
            title: 'Vibrate',
            trailing: Switch(value: draft.vibrate, onChanged: (v) => _update(draft.copyWith(vibrate: v))),
            onTap: () => _update(draft.copyWith(vibrate: !draft.vibrate)),
          ),
          OptionRow(
            icon: Icons.snooze_rounded,
            title: 'Remind me later',
            value: 'After ${draft.snoozeMinutes == 60 ? '1 hour' : '${draft.snoozeMinutes} minutes'}',
            onTap: _pickSnooze,
          ),

          const GroupGap(title: 'Note (optional)'),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
            child: TextField(
              controller: notesCtrl,
              minLines: 1,
              maxLines: 4,
              style: const TextStyle(fontSize: 15),
              textCapitalization: TextCapitalization.sentences,
              decoration: const InputDecoration(hintText: 'e.g. 1 tablet after food'),
            ),
          ),

          if (!isNew) ...[
            const SizedBox(height: 12),
            const GroupGap(),
            OptionRow(
              icon: draft.enabled ? Icons.notifications_active_rounded : Icons.notifications_off_rounded,
              title: draft.enabled ? 'Reminder is on' : 'Reminder is off',
              trailing: Switch(value: draft.enabled, onChanged: (v) => _update(draft.copyWith(enabled: v))),
              onTap: () => _update(draft.copyWith(enabled: !draft.enabled)),
            ),
            OptionRow(icon: Icons.delete_rounded, title: 'Delete reminder', color: AppColors.red, onTap: _delete),
          ],
        ],
      ),
    );
  }
}

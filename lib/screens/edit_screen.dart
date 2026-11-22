import 'dart:async';

import 'package:intl/intl.dart';
import 'package:material_ui/material_ui.dart';

import '../format.dart';
import '../models.dart';
import '../native.dart';
import '../state.dart';
import '../widgets.dart';
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
  String? error;

  bool get isNew => widget.reminder == null;

  @override
  void initState() {
    super.initState();
    final now = DateTime.now();
    final nextHour = now.add(const Duration(hours: 1));
    draft = widget.reminder ??
        Reminder(
          startDate: dateOnly(nextHour),
          hour: nextHour.hour,
          minute: 0,
          soundUri: state.setting<String?>('defaultSoundUri', null),
          soundName: state.setting<String?>('defaultSoundName', null),
          vibrate: state.setting('vibrate', true),
          snoozeMinutes: (state.settings['snoozeMinutes'] as num?)?.toInt() ?? 10,
        );
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
    // One-time templates default to tomorrow; repeating ones start today (or tomorrow if the time passed).
    // ("Every few hours" stays on today: the next slot later today is used.)
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
    setState(() {
      draft = r;
      error = null;
    });
    _refreshPreview();
  }

  void _setRepeat(RepeatRule rule) => _update(draft.copyWith(repeat: rule));

  void _refreshPreview() {
    _previewDebounce?.cancel();
    _previewDebounce = Timer(const Duration(milliseconds: 250), () async {
      try {
        final p = await Native.preview(draft.copyWith(enabled: true), count: 3);
        if (mounted) setState(() => preview = p);
      } catch (_) {}
    });
  }

  Future<void> _pickDate({bool forEnd = false}) async {
    final now = DateTime.now();
    final initial = forEnd ? (draft.repeat.endDate ?? draft.startDate.add(const Duration(days: 30))) : draft.startDate;
    final first = DateTime(now.year - 5);
    final picked = await showDatePicker(
      context: context,
      initialDate: initial.isBefore(first) ? now : initial,
      firstDate: first,
      lastDate: DateTime(now.year + 30),
      helpText: forEnd ? 'Stop repeating after' : 'Choose the date',
    );
    if (picked == null) return;
    if (forEnd) {
      _setRepeat(draft.repeat.copyWith(endDate: () => picked));
    } else {
      _update(draft.copyWith(startDate: picked));
    }
  }

  Future<void> _pickTime({bool forWindowEnd = false}) async {
    final m = forWindowEnd ? (draft.repeat.windowEnd ?? 22 * 60) : draft.hour * 60 + draft.minute;
    final picked = await showTimePicker(
      context: context,
      initialTime: TimeOfDay(hour: m ~/ 60, minute: m % 60),
      helpText: forWindowEnd ? 'Stop for the day at' : 'Remind me at',
    );
    if (picked == null) return;
    if (forWindowEnd) {
      _setRepeat(draft.repeat.copyWith(windowEnd: () => picked.hour * 60 + picked.minute));
    } else {
      _update(draft.copyWith(hour: picked.hour, minute: picked.minute));
    }
  }

  void _changeType(String type) {
    final r = draft.repeat;
    switch (type) {
      case 'weekly':
        _setRepeat(r.copyWith(type: type, interval: 1, weekdays: r.weekdays.isEmpty ? [draft.startDate.weekday] : r.weekdays));
      case 'hourly':
        final start = draft.hour * 60 + draft.minute;
        _setRepeat(r.copyWith(
          type: type,
          interval: 120,
          windowEnd: () => start < 22 * 60 ? 22 * 60 : 23 * 60 + 59,
        ));
      default:
        _setRepeat(r.copyWith(type: type, interval: 1));
    }
  }

  Future<void> _pickSound() async {
    final picked = await Navigator.of(context).push<SoundOption>(
      MaterialPageRoute(builder: (_) => SoundPickerScreen(selectedUri: draft.soundUri)),
    );
    if (picked != null) _update(draft.copyWith(soundUri: picked.uri, soundName: picked.title));
  }

  Future<void> _save() async {
    final title = titleCtrl.text.trim();
    final r = draft.copyWith(
      title: title.isEmpty ? categoryOf(draft.category).label : title,
      notes: notesCtrl.text.trim(),
      enabled: true,
    );
    if (r.repeat.type == 'once' && !r.startDateTime.isAfter(DateTime.now())) {
      setState(() => error = 'That time has already passed. Please pick a time in the future.');
      return;
    }
    if (r.repeat.endDate != null && dateOnly(r.repeat.endDate!).isBefore(dateOnly(r.startDate))) {
      setState(() => error = 'The end date is before the start date.');
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
      if (next != null && mounted) {
        messenger.showSnackBar(SnackBar(content: Text('Saved. Next alert ${fmtRelative(next)}.')));
      }
    } catch (e) {
      setState(() {
        saving = false;
        error = 'Could not save: $e';
      });
    }
  }

  Future<void> _delete() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('Delete this reminder?'),
        content: Text('"${draft.title}" will be removed and will not ring again.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Cancel')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: const Color(0xFFE5484D), minimumSize: const Size(64, 44)),
            onPressed: () => Navigator.pop(c, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (ok == true) {
      await state.delete(draft.id);
      if (mounted) Navigator.of(context).pop();
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final rule = draft.repeat;
    final hourly = rule.type == 'hourly';
    return Scaffold(
      appBar: AppBar(
        title: Text(isNew ? 'New reminder' : 'Edit reminder', style: const TextStyle(fontWeight: FontWeight.w700)),
        actions: [
          if (!isNew)
            IconButton(tooltip: 'Delete', onPressed: _delete, icon: const Icon(Icons.delete_outline_rounded)),
        ],
      ),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (error != null)
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Text(error!, style: TextStyle(color: theme.colorScheme.error, fontSize: 15)),
                ),
              SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  onPressed: saving ? null : _save,
                  icon: const Icon(Icons.check_rounded),
                  label: Text(isNew ? 'Save reminder' : 'Save changes'),
                ),
              ),
            ],
          ),
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
        children: [
          if (isNew) ...[
            _label(context, 'Quick start'),
            SizedBox(
              height: 48,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                itemCount: templates.length,
                separatorBuilder: (_, _) => const SizedBox(width: 8),
                itemBuilder: (_, i) => TemplateChip(
                  template: templates[i],
                  selected: selectedTemplate == templates[i],
                  onTap: () {
                    setState(() => _applyTemplate(templates[i]));
                    _refreshPreview();
                  },
                ),
              ),
            ),
          ],
          _label(context, 'What to remind'),
          TextField(
            controller: titleCtrl,
            textCapitalization: TextCapitalization.sentences,
            style: theme.textTheme.titleLarge,
            decoration: const InputDecoration(hintText: 'e.g. Take blood pressure tablet'),
            onChanged: (v) => draft = draft.copyWith(title: v),
          ),
          const SizedBox(height: 14),
          SizedBox(
            height: 92,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              itemCount: categories.length,
              separatorBuilder: (_, _) => const SizedBox(width: 6),
              itemBuilder: (_, i) {
                final c = categories[i];
                final sel = c.key == draft.category;
                return InkWell(
                  borderRadius: BorderRadius.circular(16),
                  onTap: () => _update(draft.copyWith(category: c.key)),
                  child: SizedBox(
                    width: 72,
                    child: Column(
                      children: [
                        AnimatedContainer(
                          duration: const Duration(milliseconds: 180),
                          width: 56,
                          height: 56,
                          decoration: BoxDecoration(
                            color: sel ? c.color : c.color.withValues(alpha: 0.12),
                            borderRadius: BorderRadius.circular(18),
                          ),
                          child: Icon(c.icon, color: sel ? Colors.white : c.color, size: 28),
                        ),
                        const SizedBox(height: 6),
                        Text(c.label,
                            style: TextStyle(
                              fontSize: 13,
                              fontWeight: sel ? FontWeight.w700 : FontWeight.w500,
                              color: sel ? c.color : theme.colorScheme.onSurfaceVariant,
                            )),
                      ],
                    ),
                  ),
                );
              },
            ),
          ),

          // ---------------- when ----------------
          Section(title: 'WHEN', children: [
            Row(
              children: [
                Expanded(
                  child: _WhenBox(
                    icon: Icons.calendar_month_rounded,
                    label: rule.type == 'once' ? 'Date' : 'Starting',
                    value: fmtDay(draft.startDate),
                    onTap: _pickDate,
                  ),
                ),
                Expanded(
                  child: _WhenBox(
                    icon: Icons.schedule_rounded,
                    label: hourly ? 'From' : 'Time',
                    value: fmtMinutesOfDay(context, draft.hour * 60 + draft.minute),
                    onTap: _pickTime,
                  ),
                ),
              ],
            ),
          ]),

          // ---------------- repeat ----------------
          Section(title: 'REPEAT', children: [
            Padding(
              padding: const EdgeInsets.all(14),
              child: Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final (type, label) in const [
                    ('once', 'Once'),
                    ('daily', 'Daily'),
                    ('weekly', 'Weekly'),
                    ('monthly', 'Monthly'),
                    ('yearly', 'Yearly'),
                    ('hourly', 'Every few hours'),
                  ])
                    ChoiceChip(
                      label: Text(label, style: const TextStyle(fontSize: 15)),
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 8),
                      selected: rule.type == type,
                      onSelected: (_) => _changeType(type),
                    ),
                ],
              ),
            ),
            if (rule.type != 'once') ...[
              const Divider(height: 1),
              Padding(padding: const EdgeInsets.all(14), child: _repeatDetails(context)),
              const Divider(height: 1),
              BigTile(
                icon: Icons.event_busy_rounded,
                label: 'Stop repeating',
                value: rule.endDate == null ? 'Never' : 'After ${DateFormat('d MMM y').format(rule.endDate!)}',
                onTap: () => _pickDate(forEnd: true),
                trailing: rule.endDate == null
                    ? null
                    : IconButton(
                        tooltip: 'Never stop',
                        onPressed: () => _setRepeat(rule.copyWith(endDate: () => null)),
                        icon: const Icon(Icons.close_rounded),
                      ),
              ),
            ],
          ]),
          if (preview.isNotEmpty)
            Padding(
              padding: const EdgeInsets.fromLTRB(8, 12, 8, 0),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(Icons.notifications_active_outlined, size: 20, color: theme.colorScheme.primary),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Next: ${preview.map((d) => fmtWhen(context, d)).join('  •  ')}',
                      style: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                    ),
                  ),
                ],
              ),
            ),

          // ---------------- alert ----------------
          Section(title: 'ALERT', children: [
            BigTile(
              icon: Icons.music_note_rounded,
              label: 'Sound',
              value: draft.soundName ?? 'Default',
              onTap: _pickSound,
            ),
            const Divider(height: 1, indent: 58),
            BigTile(
              icon: Icons.vibration_rounded,
              label: 'Vibrate',
              trailing: Switch(value: draft.vibrate, onChanged: (v) => _update(draft.copyWith(vibrate: v))),
              onTap: () => _update(draft.copyWith(vibrate: !draft.vibrate)),
            ),
            const Divider(height: 1, indent: 58),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(children: [
                    Icon(Icons.snooze_rounded, color: theme.colorScheme.primary, size: 26),
                    const SizedBox(width: 16),
                    Text('Snooze for', style: theme.textTheme.titleMedium),
                  ]),
                  const SizedBox(height: 10),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      for (final m in const [5, 10, 15, 30, 60])
                        ChoiceChip(
                          label: Text(m == 60 ? '1 hour' : '$m min'),
                          selected: draft.snoozeMinutes == m,
                          onSelected: (_) => _update(draft.copyWith(snoozeMinutes: m)),
                        ),
                    ],
                  ),
                ],
              ),
            ),
          ]),

          _label(context, 'Notes (optional)'),
          TextField(
            controller: notesCtrl,
            minLines: 2,
            maxLines: 5,
            textCapitalization: TextCapitalization.sentences,
            decoration: const InputDecoration(hintText: 'e.g. 1 tablet after food'),
          ),
        ],
      ),
    );
  }

  Widget _label(BuildContext context, String text) => Padding(
        padding: const EdgeInsets.fromLTRB(6, 18, 6, 8),
        child: Text(text.toUpperCase(),
            style: Theme.of(context).textTheme.titleSmall?.copyWith(
                  fontWeight: FontWeight.w700,
                  color: Theme.of(context).colorScheme.primary,
                  letterSpacing: 0.3,
                )),
      );

  Widget _repeatDetails(BuildContext context) {
    final rule = draft.repeat;
    final theme = Theme.of(context);
    switch (rule.type) {
      case 'daily':
        return Stepper2(
          value: rule.interval,
          max: 365,
          label: (n) => n == 1 ? 'Every day' : 'Every $n days',
          onChanged: (n) => _setRepeat(rule.copyWith(interval: n)),
        );
      case 'weekly':
        final days = rule.weekdays.toSet();
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('On these days', style: theme.textTheme.titleSmall),
            const SizedBox(height: 10),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                for (var d = 1; d <= 7; d++)
                  _DayCircle(
                    letter: weekdayLetter[d - 1],
                    tooltip: weekdayShort[d - 1],
                    selected: days.contains(d),
                    onTap: () {
                      final next = {...days};
                      if (!next.remove(d)) next.add(d);
                      if (next.isEmpty) return; // keep at least one day
                      _setRepeat(rule.copyWith(weekdays: next.toList()..sort()));
                    },
                  ),
              ],
            ),
            const SizedBox(height: 10),
            Wrap(spacing: 8, children: [
              ActionChip(label: const Text('Weekdays'), onPressed: () => _setRepeat(rule.copyWith(weekdays: [1, 2, 3, 4, 5]))),
              ActionChip(label: const Text('Weekends'), onPressed: () => _setRepeat(rule.copyWith(weekdays: [6, 7]))),
              ActionChip(label: const Text('Every day'), onPressed: () => _setRepeat(rule.copyWith(weekdays: [1, 2, 3, 4, 5, 6, 7]))),
            ]),
            const SizedBox(height: 10),
            Stepper2(
              value: rule.interval,
              max: 52,
              label: (n) => n == 1 ? 'Every week' : 'Every $n weeks',
              onChanged: (n) => _setRepeat(rule.copyWith(interval: n)),
            ),
          ],
        );
      case 'monthly':
        return Column(children: [
          Stepper2(
            value: rule.interval,
            max: 60,
            label: (n) => n == 1 ? 'Every month' : 'Every $n months',
            onChanged: (n) => _setRepeat(rule.copyWith(interval: n)),
          ),
          const SizedBox(height: 6),
          Text('On the ${ordinal(draft.startDate.day)} (change the start date to pick another day)',
              textAlign: TextAlign.center, style: theme.textTheme.bodyMedium),
        ]);
      case 'yearly':
        return Column(children: [
          Stepper2(
            value: rule.interval,
            max: 20,
            label: (n) => n == 1 ? 'Every year' : 'Every $n years',
            onChanged: (n) => _setRepeat(rule.copyWith(interval: n)),
          ),
          const SizedBox(height: 6),
          Text('On ${DateFormat('d MMMM').format(draft.startDate)}', style: theme.textTheme.bodyMedium),
        ]);
      case 'hourly':
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Remind me every', style: theme.textTheme.titleSmall),
            const SizedBox(height: 10),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final m in const [15, 30, 60, 90, 120, 180, 240, 360])
                  ChoiceChip(
                    label: Text(fmtInterval(m)),
                    selected: rule.interval == m,
                    onSelected: (_) => _setRepeat(rule.copyWith(interval: m)),
                  ),
              ],
            ),
            const SizedBox(height: 12),
            Row(children: [
              Expanded(
                child: _WhenBox(
                  icon: Icons.wb_sunny_rounded,
                  label: 'From',
                  value: fmtMinutesOfDay(context, draft.hour * 60 + draft.minute),
                  onTap: _pickTime,
                ),
              ),
              Expanded(
                child: _WhenBox(
                  icon: Icons.bedtime_rounded,
                  label: 'Until',
                  value: fmtMinutesOfDay(context, rule.windowEnd ?? 23 * 60 + 59),
                  onTap: () => _pickTime(forWindowEnd: true),
                ),
              ),
            ]),
          ],
        );
      default:
        return const SizedBox();
    }
  }
}

class _WhenBox extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  final VoidCallback onTap;
  const _WhenBox({required this.icon, required this.label, required this.value, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(16),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(children: [
              Icon(icon, size: 20, color: theme.colorScheme.primary),
              const SizedBox(width: 6),
              Text(label, style: theme.textTheme.labelLarge?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
            ]),
            const SizedBox(height: 6),
            FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.centerLeft,
              child: Text(value, style: theme.textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w700)),
            ),
          ],
        ),
      ),
    );
  }
}

class _DayCircle extends StatelessWidget {
  final String letter;
  final String tooltip;
  final bool selected;
  final VoidCallback onTap;
  const _DayCircle({required this.letter, required this.tooltip, required this.selected, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Semantics(
      label: tooltip,
      selected: selected,
      button: true,
      child: InkWell(
        customBorder: const CircleBorder(),
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          width: 42,
          height: 42,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: selected ? cs.primary : cs.surfaceContainerHighest,
          ),
          child: Text(letter,
              style: TextStyle(
                fontSize: 17,
                fontWeight: FontWeight.w700,
                color: selected ? cs.onPrimary : cs.onSurfaceVariant,
              )),
        ),
      ),
    );
  }
}

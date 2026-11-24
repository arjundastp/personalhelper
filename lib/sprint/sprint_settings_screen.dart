import 'package:material_ui/material_ui.dart';

import '../format.dart' show fmtMinutesOfDay;
import '../main.dart' show AppColors;
import '../models.dart' show SoundOption;
import '../screens/sound_picker_screen.dart';
import '../state.dart';
import '../widgets.dart';
import 'sprint_state.dart';

class SprintSettingsScreen extends StatelessWidget {
  const SprintSettingsScreen({super.key});

  Future<void> _pickTime(BuildContext context, {required bool morning}) async {
    final s = SprintState.instance;
    final m = morning ? s.morningMin : s.eveningMin;
    final picked = await showTimePicker(
      context: context,
      initialTime: TimeOfDay(hour: m ~/ 60, minute: m % 60),
      helpText: morning ? 'Morning: plan my day' : 'Evening: update my tasks',
    );
    if (picked == null) return;
    await s.update((x) {
      if (morning) {
        x.morningMin = picked.hour * 60 + picked.minute;
        x.morningOn = true;
      } else {
        x.eveningMin = picked.hour * 60 + picked.minute;
        x.eveningOn = true;
      }
    });
  }

  Future<void> _remove(BuildContext context) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('Remove Daily Sprint?'),
        content: const Text(
          'The Daily Sprint menu and its alerts go away. Your tasks and past days are kept if you add it again.',
          style: TextStyle(fontSize: 16),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Cancel')),
          TextButton(
            style: TextButton.styleFrom(foregroundColor: AppColors.red),
            onPressed: () => Navigator.pop(c, true),
            child: const Text('Remove'),
          ),
        ],
      ),
    );
    if (ok == true) {
      await SprintState.instance.setEnabled(false);
      if (context.mounted) Navigator.of(context).popUntil((r) => r.isFirst);
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = SprintState.instance;
    return ListenableBuilder(
      listenable: s,
      builder: (context, _) {
        final grey = Theme.of(context).colorScheme.onSurfaceVariant;
        return Scaffold(
          appBar: AppBar(title: const Text('Daily Sprint settings')),
          body: ListView(
            padding: const EdgeInsets.only(bottom: 32),
            children: [
              const ListHeader('Reminders'),
              OptionRow(
                icon: Icons.wb_sunny_outlined,
                title: 'Morning: plan my day',
                value: s.morningOn ? '${fmtMinutesOfDay(context, s.morningMin)} · a gentle notification · tap to change' : 'Off',
                onTap: () => _pickTime(context, morning: true),
                trailing: Switch(value: s.morningOn, onChanged: (v) => s.update((x) => x.morningOn = v)),
              ),
              OptionRow(
                icon: Icons.nightlight_outlined,
                title: 'Evening: update my tasks',
                value: s.eveningOn ? '${fmtMinutesOfDay(context, s.eveningMin)} · full-screen alert · tap to change' : 'Off',
                onTap: () => _pickTime(context, morning: false),
                trailing: Switch(value: s.eveningOn, onChanged: (v) => s.update((x) => x.eveningOn = v)),
              ),
              OptionRow(
                icon: s.soundOn ? Icons.volume_up_rounded : Icons.volume_off_rounded,
                title: 'Evening alert sound',
                value: s.soundOn ? 'On' : 'Off – only the screen alert',
                trailing: Switch(value: s.soundOn, onChanged: (v) => s.update((x) => x.soundOn = v)),
                onTap: () => s.update((x) => x.soundOn = !x.soundOn),
              ),
              if (s.soundOn)
                OptionRow(
                  icon: Icons.music_note_rounded,
                  title: 'Tune',
                  value: s.soundName ?? AppState.instance.setting('defaultSoundName', 'Default sound'),
                  onTap: () async {
                    final picked = await Navigator.of(context).push<SoundOption>(MaterialPageRoute(
                      builder: (_) => SoundPickerScreen(selectedUri: s.soundUri, title: 'Evening alert sound'),
                    ));
                    if (picked != null) {
                      await s.update((x) {
                        x.soundUri = picked.uri;
                        x.soundName = picked.title;
                      });
                    }
                  },
                ),

              const GroupGap(title: 'My work days'),
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 10, 20, 6),
                child: DayPicker(
                  selected: s.workdays.toSet(),
                  onToggle: (d) => s.update((x) {
                    final set = x.workdays.toSet();
                    if (!set.remove(d)) set.add(d);
                    x.workdays = set.toList()..sort();
                  }),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 2, 20, 10),
                child: Text('No alerts on the other days.', style: TextStyle(fontSize: 14, color: grey)),
              ),

              const GroupGap(title: 'Unfinished tasks'),
              const OptionRow(
                icon: Icons.arrow_forward_rounded,
                title: 'Move to the next work day',
                value: 'Asked each evening. Moved tasks are labelled "Moved from …" so you can mark them again.',
              ),

              const GroupGap(),
              OptionRow(
                icon: Icons.delete_outline_rounded,
                color: AppColors.red,
                title: 'Remove Daily Sprint',
                value: 'Hides the menu. Your tasks and past days are kept.',
                onTap: () => _remove(context),
              ),
            ],
          ),
        );
      },
    );
  }
}

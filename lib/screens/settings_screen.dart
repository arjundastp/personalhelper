import 'package:material_ui/material_ui.dart';

import '../main.dart' show AppColors, confirmDeviceAuth;
import '../models.dart';
import '../native.dart';
import '../sprint/sprint_state.dart';
import '../state.dart';
import '../widgets.dart';
import 'sound_picker_screen.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _Perm {
  final String key;
  final String title;
  final String why;
  final IconData icon;
  final bool critical;
  const _Perm(this.key, this.title, this.why, this.icon, {this.critical = false});
}

const _perms = [
  _Perm('notifications', 'Allow notifications', 'Needed to show reminders', Icons.notifications_active_rounded, critical: true),
  _Perm('fullScreen', 'Allow full-screen alert', 'Shows the big alert on the lock screen', Icons.fullscreen_rounded, critical: true),
  _Perm('exactAlarm', 'Allow alarms', 'Rings at the exact minute', Icons.alarm_on_rounded, critical: true),
  _Perm('battery', 'Don\'t limit battery', 'So your phone does not stop reminders', Icons.battery_charging_full_rounded),
  _Perm('overlay', 'Show on top of other apps', 'Shows the alert while you use other apps', Icons.layers_rounded),
  _Perm('dnd', 'Ring in "Do not disturb"', 'Rings even in total silence mode', Icons.do_not_disturb_on_rounded),
];

class _SettingsScreenState extends State<SettingsScreen> {
  final state = AppState.instance;

  int _int(String k, int d) => (state.settings[k] as num?)?.toInt() ?? d;

  String? get _phoneTip {
    final m = state.manufacturer;
    if (m.contains('xiaomi') || m.contains('redmi') || m.contains('poco')) {
      return 'Xiaomi / Redmi / POCO phones: in App info, turn on "Autostart" and set Battery saver to "No restrictions".';
    }
    if (m.contains('oppo') || m.contains('realme') || m.contains('oneplus')) {
      return 'OPPO / realme / OnePlus phones: in App info, allow "Auto launch" and "Allow background activity".';
    }
    if (m.contains('vivo') || m.contains('iqoo')) {
      return 'vivo / iQOO phones: in App info, allow "Autostart" and "High background power consumption".';
    }
    if (m.contains('huawei') || m.contains('honor')) {
      return 'Huawei / Honor phones: in App launch, turn off "Manage automatically" and allow all options.';
    }
    if (m.contains('samsung')) {
      return 'Samsung phones: make sure DayMate is not in "Sleeping apps" in Battery settings.';
    }
    return null;
  }

  Future<void> _toggleLock(bool on) async {
    if (on && !await confirmDeviceAuth()) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('First set a fingerprint, PIN or pattern in your phone settings.', style: TextStyle(fontSize: 14.5)),
        ));
      }
      return;
    }
    await state.updateSettings({'appLock': on});
  }

  Future<void> _pick(String title, String key, List<(int, String)> options, int current) async {
    final v = await chooseOne<int>(context, title: title, options: options, current: current);
    if (v != null) await state.updateSettings({key: v});
  }

  Future<void> _test() async {
    await Native.testAlarm(seconds: 5);
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
      duration: Duration(seconds: 5),
      content: Text('A test alert will ring in 5 seconds. You can lock your phone now.', style: TextStyle(fontSize: 14.5)),
    ));
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final grey = theme.colorScheme.onSurfaceVariant;
    return ListenableBuilder(
      listenable: state,
      builder: (context, _) {
        final p = state.permissions;
        final missing = _perms.where((x) => p[x.key] == false).toList();
        final criticalMissing = missing.where((x) => x.critical).isNotEmpty;
        final ringMin = _int('ringMinutes', 2);
        final autoRepeat = _int('autoRepeat', 3);
        final theme0 = state.setting('themeMode', 'system');

        return Scaffold(
          appBar: AppBar(title: const Text('Settings')),
          body: ListView(
            padding: const EdgeInsets.only(bottom: 32),
            children: [
              // ---- status ----
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 16, 20, 10),
                child: Row(children: [
                  Container(
                    width: 52,
                    height: 52,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: (criticalMissing ? AppColors.red : AppColors.accent).withValues(alpha: 0.15),
                    ),
                    child: Icon(criticalMissing ? Icons.priority_high_rounded : Icons.check_rounded,
                        size: 28, color: criticalMissing ? AppColors.red : AppColors.accent),
                  ),
                  const SizedBox(width: 18),
                  Expanded(
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text(
                        criticalMissing ? 'Reminders may not ring' : 'Reminders will ring',
                        style: const TextStyle(fontSize: 17.5, fontWeight: FontWeight.w600),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        missing.isEmpty
                            ? 'Everything is set up.'
                            : 'Tap "Allow" below. ${missing.length} item${missing.length == 1 ? '' : 's'} left.',
                        style: TextStyle(fontSize: 13.5, color: grey),
                      ),
                    ]),
                  ),
                ]),
              ),
              for (final x in missing)
                OptionRow(
                  icon: x.icon,
                  color: x.critical ? AppColors.red : null,
                  title: x.title,
                  value: x.why,
                  trailing: FilledButton(
                    style: FilledButton.styleFrom(minimumSize: const Size(72, 36), padding: const EdgeInsets.symmetric(horizontal: 14)),
                    onPressed: () async {
                      await Native.requestPermission(x.key);
                      await state.refreshPermissions();
                    },
                    child: const Text('Allow'),
                  ),
                  onTap: () async {
                    await Native.requestPermission(x.key);
                    await state.refreshPermissions();
                  },
                ),
              if (_phoneTip != null)
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 4, 20, 8),
                  child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Icon(Icons.lightbulb_outline_rounded, size: 22, color: grey),
                    const SizedBox(width: 12),
                    Expanded(child: Text(_phoneTip!, style: TextStyle(fontSize: 13, color: grey))),
                  ]),
                ),
              OptionRow(
                icon: Icons.play_circle_outline_rounded,
                color: theme.brightness == Brightness.light ? AppColors.green : AppColors.accent,
                title: 'Try a test alert',
                value: 'Rings in 5 seconds',
                onTap: _test,
              ),

              // ---- sound ----
              const GroupGap(title: 'Sound'),
              OptionRow(
                icon: Icons.music_note_rounded,
                title: 'Default sound',
                value: state.setting('defaultSoundName', 'Gentle Chime'),
                onTap: () async {
                  final picked = await Navigator.of(context).push<SoundOption>(MaterialPageRoute(
                    builder: (_) => SoundPickerScreen(
                        selectedUri: state.setting<String?>('defaultSoundUri', null), title: 'Default sound'),
                  ));
                  if (picked != null) {
                    await state.updateSettings({'defaultSoundUri': picked.uri, 'defaultSoundName': picked.title});
                  }
                },
              ),
              OptionRow(
                icon: Icons.timer_outlined,
                title: 'Ring for',
                value: ringMin == 1 ? '1 minute' : '$ringMin minutes',
                onTap: () => _pick('Ring for', 'ringMinutes',
                    const [(1, '1 minute'), (2, '2 minutes'), (3, '3 minutes'), (5, '5 minutes'), (10, '10 minutes')], ringMin),
              ),
              OptionRow(
                icon: Icons.replay_rounded,
                title: 'If I don\'t answer',
                value: autoRepeat == 0 ? 'Don\'t ring again' : 'Ring again $autoRepeat time${autoRepeat == 1 ? '' : 's'}',
                onTap: () => _pick('If I don\'t answer', 'autoRepeat', const [
                  (0, 'Don\'t ring again'),
                  (1, 'Ring again 1 time'),
                  (2, 'Ring again 2 times'),
                  (3, 'Ring again 3 times'),
                  (5, 'Ring again 5 times'),
                ], autoRepeat),
              ),
              _switch(Icons.volume_up_rounded, 'Always ring loud', 'Turns up the volume if it is too low', 'ensureVolume', true),
              _switch(Icons.trending_up_rounded, 'Start softly', 'Sound gets louder slowly', 'gradualVolume', true),
              _switch(Icons.vibration_rounded, 'Vibrate', null, 'vibrate', true),

              // ---- extras ----
              const GroupGap(title: 'Extras'),
              const _SprintCard(),

              // ---- lock ----
              const GroupGap(title: 'Privacy'),
              _switchRaw(
                Icons.fingerprint_rounded,
                'Lock with fingerprint',
                'Ask for fingerprint or phone PIN to open',
                state.setting('appLock', false),
                _toggleLock,
              ),
              const OptionRow(
                icon: Icons.lock_outline_rounded,
                title: 'Saved only on this phone',
                value: 'No internet. Nothing is sent anywhere.',
              ),

              // ---- look ----
              const GroupGap(title: 'Display'),
              OptionRow(
                icon: Icons.brightness_6_rounded,
                title: 'Theme',
                value: switch (theme0) { 'light' => 'Light', 'dark' => 'Dark', _ => 'Same as phone' },
                onTap: () async {
                  final v = await chooseOne<String>(context,
                      title: 'Theme',
                      options: const [('system', 'Same as phone'), ('light', 'Light'), ('dark', 'Dark')],
                      current: theme0);
                  if (v != null) await state.updateSettings({'themeMode': v});
                },
              ),
              if (SprintState.instance.enabled)
                OptionRow(
                  icon: Icons.open_in_new_rounded,
                  title: 'Open app on',
                  value: switch (state.setting('startTab', 'reminders')) {
                    'sprint' => 'Daily Sprint',
                    'last' => 'The menu I used last',
                    _ => 'Reminders',
                  },
                  onTap: () async {
                    final v = await chooseOne<String>(context,
                        title: 'Open app on',
                        options: const [('reminders', 'Reminders'), ('sprint', 'Daily Sprint'), ('last', 'The menu I used last')],
                        current: state.setting('startTab', 'reminders'));
                    if (v != null) await state.updateSettings({'startTab': v});
                  },
                ),
              _switch(Icons.format_size_rounded, 'Bigger text', 'Easier to read', 'largeText', false),
              const SizedBox(height: 24),
              Center(child: Text('DayMate 1.6', style: TextStyle(fontSize: 13, color: grey))),
            ],
          ),
        );
      },
    );
  }

  Widget _switch(IconData icon, String title, String? value, String key, bool fallback) =>
      _switchRaw(icon, title, value, state.setting(key, fallback), (v) => state.updateSettings({key: v}));

  Widget _switchRaw(IconData icon, String title, String? value, bool on, ValueChanged<bool> onChanged) => OptionRow(
        icon: icon,
        title: title,
        value: value,
        trailing: Switch(value: on, onChanged: onChanged),
        onTap: () => onChanged(!on),
      );
}

/// "Add Daily Sprint": the optional work-day planner, hidden until added here.
class _SprintCard extends StatelessWidget {
  const _SprintCard();

  @override
  Widget build(BuildContext context) {
    final sprint = SprintState.instance;
    final theme = Theme.of(context);
    final grey = theme.colorScheme.onSurfaceVariant;
    final light = theme.brightness == Brightness.light;
    return ListenableBuilder(
      listenable: sprint,
      builder: (context, _) {
        final on = sprint.enabled;
        return Container(
          margin: const EdgeInsets.fromLTRB(16, 10, 16, 4),
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: on ? AppColors.accent.withValues(alpha: 0.06) : null,
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: on ? AppColors.accent : theme.colorScheme.outlineVariant, width: 1.5),
          ),
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Container(
                width: 52,
                height: 52,
                decoration: BoxDecoration(color: const Color(0xFF3E63DD).withValues(alpha: 0.13), shape: BoxShape.circle),
                child: const Icon(Icons.assignment_turned_in_outlined, color: Color(0xFF3E63DD), size: 26),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  const Text('Daily Sprint', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600)),
                  const SizedBox(height: 3),
                  Text('Plan your small work tasks each morning. Every evening it asks you which ones got done.',
                      style: TextStyle(fontSize: 13, color: grey, height: 1.35)),
                ]),
              ),
            ]),
            const SizedBox(height: 14),
            if (on)
              Row(children: [
                Icon(Icons.check_rounded, color: light ? AppColors.green : AppColors.accent, size: 22),
                const SizedBox(width: 6),
                Expanded(
                  child: Text('Added – see the bottom menu',
                      style: TextStyle(fontSize: 15.5, fontWeight: FontWeight.w600, color: light ? AppColors.green : AppColors.accent)),
                ),
                OutlinedButton(
                  style: OutlinedButton.styleFrom(foregroundColor: AppColors.red, minimumSize: const Size(0, 44)),
                  onPressed: () => sprint.setEnabled(false),
                  child: const Text('Remove'),
                ),
              ])
            else
              FilledButton.icon(
                onPressed: () async {
                  await sprint.setEnabled(true);
                  if (context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
                      content: Text('Daily Sprint added. Find it in the bottom menu.', style: TextStyle(fontSize: 14.5)),
                    ));
                  }
                },
                icon: const Icon(Icons.add_rounded),
                label: const Text('Add Daily Sprint'),
              ),
          ]),
        );
      },
    );
  }
}

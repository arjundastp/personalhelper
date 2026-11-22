import 'package:material_ui/material_ui.dart';

import '../main.dart' show confirmDeviceAuth;
import '../models.dart';
import '../native.dart';
import '../state.dart';
import '../widgets.dart';
import 'sound_picker_screen.dart';

class SettingsScreen extends StatefulWidget {
  final bool focusReliability;
  const SettingsScreen({super.key, this.focusReliability = false});

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
  _Perm('notifications', 'Notifications', 'Needed to show any reminder.', Icons.notifications_active_rounded, critical: true),
  _Perm('fullScreen', 'Full-screen alerts', 'Shows the big alert over the lock screen.', Icons.fullscreen_rounded,
      critical: true),
  _Perm('exactAlarm', 'Exact timing', 'Rings at the exact minute, even in battery saver.', Icons.timer_rounded,
      critical: true),
  _Perm('battery', 'No battery limits', 'Stops the phone from putting Remindly to sleep.', Icons.battery_charging_full_rounded),
  _Perm('dnd', 'Do Not Disturb access', 'Lets alerts ring even in "Total silence" mode.', Icons.do_not_disturb_on_rounded),
  _Perm('overlay', 'Show over other apps', 'Opens the full-screen alert even while you use the phone.',
      Icons.layers_rounded),
];

class _SettingsScreenState extends State<SettingsScreen> {
  final state = AppState.instance;

  int _int(String k, int d) => (state.settings[k] as num?)?.toInt() ?? d;

  String? get _oemTip {
    final m = state.manufacturer;
    if (m.contains('xiaomi') || m.contains('redmi') || m.contains('poco')) {
      return 'On Xiaomi / Redmi / POCO phones also turn on "Autostart" for Remindly and set Battery saver to "No restrictions" (App info).';
    }
    if (m.contains('oppo') || m.contains('realme') || m.contains('oneplus')) {
      return 'On OPPO / realme / OnePlus phones also allow "Auto launch" and set Battery usage to "Allow background activity" (App info).';
    }
    if (m.contains('vivo') || m.contains('iqoo')) {
      return 'On vivo / iQOO phones also allow "Autostart" and "High background power consumption" (App info).';
    }
    if (m.contains('huawei') || m.contains('honor')) {
      return 'On Huawei / Honor phones open App launch, turn off "Manage automatically" and allow all three options.';
    }
    if (m.contains('samsung')) {
      return 'On Samsung phones make sure Remindly is not in "Sleeping apps" or "Deep sleeping apps" (Battery settings).';
    }
    return null;
  }

  Future<void> _toggleLock(bool on) async {
    if (on) {
      final ok = await confirmDeviceAuth();
      if (!ok) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
            content: Text('Set up a fingerprint, PIN or pattern on your phone first, then try again.'),
          ));
        }
        return;
      }
    }
    await state.updateSettings({'appLock': on});
  }

  Future<void> _pickDefaultSound() async {
    final picked = await Navigator.of(context).push<SoundOption>(MaterialPageRoute(
      builder: (_) => SoundPickerScreen(selectedUri: state.setting<String?>('defaultSoundUri', null), title: 'Default sound'),
    ));
    if (picked != null) await state.updateSettings({'defaultSoundUri': picked.uri, 'defaultSoundName': picked.title});
  }

  Future<void> _choose(String title, String key, List<(int, String)> options, int current) async {
    final v = await showModalBottomSheet<int>(
      context: context,
      showDragHandle: true,
      builder: (c) => SafeArea(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(24, 0, 24, 8),
            child: Text(title, style: Theme.of(c).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700)),
          ),
          for (final (val, label) in options)
            ListTile(
              contentPadding: const EdgeInsets.symmetric(horizontal: 24),
              title: Text(label, style: const TextStyle(fontSize: 17)),
              trailing: val == current ? Icon(Icons.check_rounded, color: Theme.of(c).colorScheme.primary) : null,
              onTap: () => Navigator.pop(c, val),
            ),
          const SizedBox(height: 12),
        ]),
      ),
    );
    if (v != null) await state.updateSettings({key: v});
  }

  Future<void> _test() async {
    await Native.testAlarm(seconds: 5);
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
      duration: Duration(seconds: 5),
      content: Text('A test alert will ring in 5 seconds. Lock your phone to see how it looks on the lock screen.'),
    ));
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return ListenableBuilder(
      listenable: state,
      builder: (context, _) {
        final p = state.permissions;
        final allOk = _perms.every((x) => p[x.key] != false);
        final ringMin = _int('ringMinutes', 2);
        final autoRepeat = _int('autoRepeat', 3);
        final snooze = _int('snoozeMinutes', 10);
        return Scaffold(
          appBar: AppBar(title: const Text('Settings', style: TextStyle(fontWeight: FontWeight.w700))),
          body: ListView(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 32),
            children: [
              Section(
                title: 'MAKE SURE ALERTS RING',
                trailing: allOk
                    ? const Row(mainAxisSize: MainAxisSize.min, children: [
                        Icon(Icons.verified_rounded, color: Color(0xFF30A46C), size: 20),
                        SizedBox(width: 4),
                        Text('All set', style: TextStyle(color: Color(0xFF30A46C), fontWeight: FontWeight.w700)),
                      ])
                    : null,
                children: [
                  for (final x in _perms) ...[
                    _permRow(context, x, p[x.key] ?? true),
                    if (x != _perms.last) const Divider(height: 1, indent: 58),
                  ],
                ],
              ),
              if (_oemTip != null)
                Padding(
                  padding: const EdgeInsets.fromLTRB(6, 10, 6, 0),
                  child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Icon(Icons.info_outline_rounded, size: 20, color: theme.colorScheme.primary),
                    const SizedBox(width: 8),
                    Expanded(child: Text(_oemTip!, style: theme.textTheme.bodyMedium)),
                  ]),
                ),
              const SizedBox(height: 12),
              OutlinedButton.icon(
                style: OutlinedButton.styleFrom(minimumSize: const Size(64, 56)),
                onPressed: _test,
                icon: const Icon(Icons.play_arrow_rounded),
                label: const Text('Test an alert now', style: TextStyle(fontSize: 16)),
              ),

              Section(title: 'ALERTS', children: [
                BigTile(
                  icon: Icons.music_note_rounded,
                  label: 'Default sound',
                  value: state.setting('defaultSoundName', 'Gentle Chime'),
                  onTap: _pickDefaultSound,
                ),
                const Divider(height: 1, indent: 58),
                BigTile(
                  icon: Icons.timelapse_rounded,
                  label: 'Ring for',
                  value: ringMin == 1 ? '1 minute' : '$ringMin minutes',
                  onTap: () => _choose('Ring for', 'ringMinutes',
                      [(1, '1 minute'), (2, '2 minutes'), (3, '3 minutes'), (5, '5 minutes'), (10, '10 minutes')], ringMin),
                ),
                const Divider(height: 1, indent: 58),
                BigTile(
                  icon: Icons.replay_rounded,
                  label: 'If I don\'t answer',
                  value: autoRepeat == 0 ? 'Don\'t ring again' : 'Ring again up to $autoRepeat times',
                  onTap: () => _choose('If I don\'t answer', 'autoRepeat', [
                    (0, 'Don\'t ring again'),
                    (1, 'Ring again once'),
                    (2, 'Ring again 2 times'),
                    (3, 'Ring again 3 times'),
                    (5, 'Ring again 5 times'),
                  ], autoRepeat),
                ),
                const Divider(height: 1, indent: 58),
                BigTile(
                  icon: Icons.snooze_rounded,
                  label: 'Default snooze',
                  value: '$snooze minutes',
                  onTap: () => _choose('Default snooze', 'snoozeMinutes',
                      [(5, '5 minutes'), (10, '10 minutes'), (15, '15 minutes'), (30, '30 minutes'), (60, '1 hour')], snooze),
                ),
                const Divider(height: 1, indent: 58),
                _switch(Icons.trending_up_rounded, 'Start softly', 'Volume rises gradually', 'gradualVolume', true),
                const Divider(height: 1, indent: 58),
                _switch(Icons.volume_up_rounded, 'Always loud enough',
                    'Raises alarm volume to at least ${_int('minVolume', 70)}% while ringing', 'ensureVolume', true),
                if (state.setting('ensureVolume', true))
                  Padding(
                    padding: const EdgeInsets.fromLTRB(50, 0, 16, 8),
                    child: Slider(
                      value: _int('minVolume', 70).toDouble(),
                      min: 30,
                      max: 100,
                      divisions: 7,
                      label: '${_int('minVolume', 70)}%',
                      onChanged: (v) => state.updateSettings({'minVolume': v.round()}),
                    ),
                  ),
                const Divider(height: 1, indent: 58),
                _switch(Icons.do_not_disturb_off_rounded, 'Ring in Do Not Disturb',
                    'Breaks through "Total silence" (needs DND access above)', 'overrideDnd', true),
                const Divider(height: 1, indent: 58),
                _switch(Icons.vibration_rounded, 'Vibrate by default', null, 'vibrate', true),
              ]),

              Section(title: 'PRIVACY & SECURITY', children: [
                BigTile(
                  icon: Icons.fingerprint_rounded,
                  label: 'App lock',
                  value: 'Ask for fingerprint or screen lock to open Remindly',
                  trailing: Switch(value: state.setting('appLock', false), onChanged: _toggleLock),
                  onTap: () => _toggleLock(!state.setting('appLock', false)),
                ),
                const Divider(height: 1, indent: 58),
                const BigTile(
                  icon: Icons.phonelink_lock_rounded,
                  label: 'Stored only on this phone',
                  value: 'Remindly works fully offline. Nothing is uploaded.',
                ),
              ]),

              Section(title: 'APPEARANCE', children: [
                Padding(
                  padding: const EdgeInsets.all(14),
                  child: SegmentedButton<String>(
                    style: const ButtonStyle(minimumSize: WidgetStatePropertyAll(Size(0, 48))),
                    segments: const [
                      ButtonSegment(value: 'system', label: Text('Auto'), icon: Icon(Icons.brightness_auto_rounded)),
                      ButtonSegment(value: 'light', label: Text('Light'), icon: Icon(Icons.light_mode_rounded)),
                      ButtonSegment(value: 'dark', label: Text('Dark'), icon: Icon(Icons.dark_mode_rounded)),
                    ],
                    selected: {state.setting('themeMode', 'system')},
                    onSelectionChanged: (s) => state.updateSettings({'themeMode': s.first}),
                  ),
                ),
                const Divider(height: 1, indent: 58),
                _switch(Icons.text_increase_rounded, 'Larger text', 'Makes everything easier to read', 'largeText', false),
              ]),
              const SizedBox(height: 24),
              Center(
                child: Text('Remindly 1.0', style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.outline)),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _switch(IconData icon, String label, String? value, String key, bool fallback) {
    final on = state.setting(key, fallback);
    return BigTile(
      icon: icon,
      label: label,
      value: value,
      trailing: Switch(value: on, onChanged: (v) => state.updateSettings({key: v})),
      onTap: () => state.updateSettings({key: !on}),
    );
  }

  Widget _permRow(BuildContext context, _Perm x, bool granted) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Row(children: [
        Icon(x.icon, size: 26, color: granted ? const Color(0xFF30A46C) : (x.critical ? const Color(0xFFE5484D) : const Color(0xFFF76B15))),
        const SizedBox(width: 16),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(x.title, style: theme.textTheme.titleMedium),
            Text(x.critical ? x.why : 'Recommended · ${x.why}',
                style: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
          ]),
        ),
        const SizedBox(width: 8),
        granted
            ? const Icon(Icons.check_circle_rounded, color: Color(0xFF30A46C), size: 28)
            : FilledButton.tonal(
                style: FilledButton.styleFrom(minimumSize: const Size(72, 44)),
                onPressed: () async {
                  await Native.requestPermission(x.key);
                  await state.refreshPermissions();
                },
                child: const Text('Allow'),
              ),
      ]),
    );
  }
}

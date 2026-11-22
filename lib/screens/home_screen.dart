import 'dart:async';

import 'package:material_ui/material_ui.dart';

import '../main.dart' show AppColors;
import '../models.dart';
import '../native.dart';
import '../state.dart';
import '../widgets.dart';
import 'edit_screen.dart';
import 'history_screen.dart';
import 'settings_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final state = AppState.instance;
  Timer? _tick;
  StreamSubscription<void>? _historySub;

  @override
  void initState() {
    super.initState();
    _tick = Timer.periodic(const Duration(seconds: 30), (_) => mounted ? setState(() {}) : null);
    _historySub = state.openHistoryRequests.stream.listen((_) => _open(const HistoryScreen()));
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!state.setting('onboarded', false)) _welcome();
    });
  }

  @override
  void dispose() {
    _tick?.cancel();
    _historySub?.cancel();
    super.dispose();
  }

  Future<void> _open(Widget screen) => Navigator.of(context).push(MaterialPageRoute(builder: (_) => screen));

  /// Long-press menu: simple, clearly worded choices.
  Future<void> _actions(Reminder r) async {
    final on = r.enabled;
    final choice = await showModalBottomSheet<String>(
      context: context,
      builder: (c) => SafeArea(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(24, 0, 24, 8),
            child: Row(children: [
              CategoryAvatar(category: r.category, size: 44),
              const SizedBox(width: 14),
              Expanded(child: Text(r.title, style: const TextStyle(fontSize: 19, fontWeight: FontWeight.w600))),
            ]),
          ),
          OptionRow(icon: Icons.edit_rounded, title: 'Change', onTap: () => Navigator.pop(c, 'edit')),
          OptionRow(
            icon: on ? Icons.notifications_off_rounded : Icons.notifications_active_rounded,
            title: on ? 'Turn off' : 'Turn on',
            onTap: () => Navigator.pop(c, 'toggle'),
          ),
          OptionRow(
            icon: Icons.delete_rounded,
            title: 'Delete',
            color: AppColors.red,
            onTap: () => Navigator.pop(c, 'delete'),
          ),
          const SizedBox(height: 8),
        ]),
      ),
    );
    if (!mounted) return;
    switch (choice) {
      case 'edit':
        _open(EditScreen(reminder: r));
      case 'toggle':
        await state.setEnabled(r, !on);
        _toast(on ? 'Turned off. It will not ring.' : 'Turned on.');
      case 'delete':
        if (await confirmDelete(context, r)) {
          await state.delete(r.id);
          _toast('Deleted', undo: () => state.save(r.copyWith(id: 0)));
        }
    }
  }

  void _toast(String text, {VoidCallback? undo}) {
    if (!mounted) return;
    final m = ScaffoldMessenger.of(context);
    m.clearSnackBars();
    m.showSnackBar(SnackBar(
      content: Text(text, style: const TextStyle(fontSize: 16)),
      action: undo == null ? null : SnackBarAction(label: 'UNDO', onPressed: undo),
    ));
  }

  Future<void> _welcome() async {
    await showModalBottomSheet<void>(
      context: context,
      isDismissible: false,
      enableDrag: false,
      isScrollControlled: true,
      showDragHandle: false,
      builder: (c) {
        Widget point(IconData i, String t) => Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: Row(children: [
                Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(color: AppColors.accent.withValues(alpha: 0.15), shape: BoxShape.circle),
                  child: Icon(i, color: AppColors.accent, size: 24),
                ),
                const SizedBox(width: 16),
                Expanded(child: Text(t, style: const TextStyle(fontSize: 16.5))),
              ]),
            );
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(24, 28, 24, 16),
            child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
              const Text('Welcome to Remindly', style: TextStyle(fontSize: 24, fontWeight: FontWeight.w700)),
              const SizedBox(height: 12),
              point(Icons.fullscreen_rounded, 'When it is time, your phone shows a big alert, even when it is locked.'),
              point(Icons.volume_up_rounded, 'It rings even if your phone is on silent.'),
              point(Icons.lock_outline_rounded, 'Everything stays on your phone. No internet needed.'),
              const SizedBox(height: 12),
              const Text('On the next screen, please tap "Allow".',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
              const SizedBox(height: 20),
              SizedBox(
                width: double.infinity,
                child: FilledButton(
                  onPressed: () async {
                    await Native.requestPermission('notifications');
                    await state.refreshPermissions();
                    if (state.permissions['fullScreen'] == false) await Native.requestPermission('fullScreen');
                    if (c.mounted) Navigator.pop(c);
                  },
                  child: const Text('Continue'),
                ),
              ),
            ]),
          ),
        );
      },
    );
    await state.updateSettings({'onboarded': true});
    await state.refreshPermissions();
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: state,
      builder: (context, _) {
        final upcoming = state.upcoming;
        final inactive = state.inactive;
        final today = dateOnly(DateTime.now());
        final groups = <String, List<Reminder>>{};
        for (final r in upcoming) {
          final d = dateOnly(r.nextAlert!).difference(today).inDays;
          final key = d <= 0 ? 'Today' : (d == 1 ? 'Tomorrow' : 'Coming up');
          groups.putIfAbsent(key, () => []).add(r);
        }

        return Scaffold(
          appBar: AppBar(
            title: const Text('Remindly'),
            actions: [
              PopupMenuButton<String>(
                tooltip: 'More',
                icon: Badge(
                  isLabelVisible: state.missingCritical.isNotEmpty || state.unseenMissed > 0,
                  smallSize: 9,
                  child: const Icon(Icons.more_vert_rounded),
                ),
                onSelected: (v) => _open(v == 'history' ? const HistoryScreen() : const SettingsScreen()),
                itemBuilder: (_) => const [
                  PopupMenuItem(value: 'history', child: Text('History', style: TextStyle(fontSize: 16))),
                  PopupMenuItem(value: 'settings', child: Text('Settings', style: TextStyle(fontSize: 16))),
                ],
              ),
            ],
          ),
          floatingActionButton: FloatingActionButton.extended(
            onPressed: () => _open(const EditScreen()),
            icon: const Icon(Icons.add_alarm_rounded, size: 26),
            label: const Text('Add reminder'),
          ),
          body: !state.loaded
              ? const Center(child: CircularProgressIndicator())
              : ListView(
                  padding: const EdgeInsets.only(bottom: 110),
                  children: [
                    if (state.missingCritical.isNotEmpty)
                      BannerRow(
                        icon: Icons.warning_amber_rounded,
                        color: AppColors.red,
                        title: 'Reminders may not ring',
                        subtitle: 'Tap here to fix it',
                        onTap: () => _open(const SettingsScreen()),
                      ),
                    if (state.unseenMissed > 0)
                      BannerRow(
                        icon: Icons.notification_important_rounded,
                        color: const Color(0xFFF76B15),
                        title: 'You missed ${state.unseenMissed} reminder${state.unseenMissed == 1 ? '' : 's'}',
                        subtitle: 'Tap to see them',
                        onTap: () => _open(const HistoryScreen()),
                      ),
                    if (state.reminders.isEmpty) _EmptyState(onAdd: (t) => _open(EditScreen(template: t))),
                    for (final e in groups.entries) ...[
                      ListHeader(e.key),
                      ..._rows(e.value),
                    ],
                    if (inactive.isNotEmpty) ...[
                      const ListHeader('Turned off / finished'),
                      ..._rows(inactive),
                    ],
                    if (state.reminders.isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.fromLTRB(24, 20, 24, 0),
                        child: Text(
                          'Tap a reminder to change it. Press and hold for more options.',
                          textAlign: TextAlign.center,
                          style: TextStyle(fontSize: 14, color: Theme.of(context).colorScheme.onSurfaceVariant),
                        ),
                      ),
                  ],
                ),
        );
      },
    );
  }

  List<Widget> _rows(List<Reminder> items) => [
        for (var i = 0; i < items.length; i++) ...[
          ReminderRow(
            reminder: items[i],
            onTap: () => _open(EditScreen(reminder: items[i])),
            onLongPress: () => _actions(items[i]),
          ),
          if (i < items.length - 1) const Divider(indent: 86),
        ],
      ];
}

Future<bool> confirmDelete(BuildContext context, Reminder r) async {
  final ok = await showDialog<bool>(
    context: context,
    builder: (c) => AlertDialog(
      title: const Text('Delete this reminder?'),
      content: Text('"${r.title}" will not ring again.', style: const TextStyle(fontSize: 16)),
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
  return ok == true;
}

class _EmptyState extends StatelessWidget {
  final ValueChanged<Template?> onAdd;
  const _EmptyState({required this.onAdd});

  @override
  Widget build(BuildContext context) {
    final grey = Theme.of(context).colorScheme.onSurfaceVariant;
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 40, 24, 0),
      child: Column(
        children: [
          Container(
            width: 120,
            height: 120,
            decoration: BoxDecoration(color: AppColors.accent.withValues(alpha: 0.12), shape: BoxShape.circle),
            child: const Icon(Icons.alarm_add_rounded, size: 60, color: AppColors.accent),
          ),
          const SizedBox(height: 20),
          const Text('No reminders yet', style: TextStyle(fontSize: 22, fontWeight: FontWeight.w700)),
          const SizedBox(height: 6),
          Text('Tap one below to start quickly', textAlign: TextAlign.center, style: TextStyle(fontSize: 16, color: grey)),
          const SizedBox(height: 20),
          for (final t in templates.take(5))
            Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  style: OutlinedButton.styleFrom(
                    alignment: Alignment.centerLeft,
                    padding: const EdgeInsets.symmetric(horizontal: 20),
                  ),
                  onPressed: () => onAdd(t),
                  icon: Icon(categoryOf(t.category).icon, color: categoryOf(t.category).color),
                  label: Text(t.label),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

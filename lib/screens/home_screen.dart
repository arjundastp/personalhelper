import 'dart:async';

import 'package:intl/intl.dart';
import 'package:material_ui/material_ui.dart';

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
    // Keep "in 5 min" labels fresh.
    _tick = Timer.periodic(const Duration(seconds: 30), (_) => mounted ? setState(() {}) : null);
    _historySub = state.openHistoryRequests.stream.listen((_) => _openHistory());
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!state.setting('onboarded', false)) _welcome();
    });
  }

  /// First launch: explain why permissions matter and ask for the essential ones.
  Future<void> _welcome() async {
    await showModalBottomSheet<void>(
      context: context,
      isDismissible: false,
      enableDrag: false,
      isScrollControlled: true,
      builder: (c) {
        final theme = Theme.of(c);
        Widget point(IconData i, String t) => Padding(
              padding: const EdgeInsets.symmetric(vertical: 6),
              child: Row(children: [
                Icon(i, color: theme.colorScheme.primary, size: 28),
                const SizedBox(width: 14),
                Expanded(child: Text(t, style: theme.textTheme.bodyLarge)),
              ]),
            );
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(24, 28, 24, 16),
            child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('Welcome to Remindly', style: theme.textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w800)),
              const SizedBox(height: 12),
              point(Icons.fullscreen_rounded, 'Reminders ring with a big full-screen alert, even on the lock screen.'),
              point(Icons.volume_up_rounded, 'They use the alarm volume, so they ring even when the phone is on silent.'),
              point(Icons.phonelink_lock_rounded, 'Everything stays on this phone. No account, no internet.'),
              const SizedBox(height: 8),
              Text('Next, Android will ask to allow notifications. Please tap "Allow".', style: theme.textTheme.bodyMedium),
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
  void dispose() {
    _tick?.cancel();
    _historySub?.cancel();
    super.dispose();
  }

  void _openHistory() =>
      Navigator.of(context).push(MaterialPageRoute(builder: (_) => const HistoryScreen()));

  Future<void> _openEditor([Reminder? r, Template? t]) async {
    await Navigator.of(context).push(MaterialPageRoute(builder: (_) => EditScreen(reminder: r, template: t)));
  }

  String get _greeting {
    final h = DateTime.now().hour;
    if (h < 5) return 'Good night';
    if (h < 12) return 'Good morning';
    if (h < 17) return 'Good afternoon';
    return 'Good evening';
  }

  Future<void> _delete(Reminder r) async {
    final messenger = ScaffoldMessenger.of(context);
    await state.delete(r.id);
    messenger.clearSnackBars();
    messenger.showSnackBar(SnackBar(
      content: Text('Deleted "${r.title}"'),
      action: SnackBarAction(label: 'Undo', onPressed: () => state.save(r.copyWith(id: 0))),
    ));
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return ListenableBuilder(
      listenable: state,
      builder: (context, _) {
        final upcoming = state.upcoming;
        final inactive = state.inactive;
        final today = dateOnly(DateTime.now());
        final groups = <String, List<Reminder>>{};
        for (final r in upcoming.skip(1)) {
          final d = dateOnly(r.nextAlert!).difference(today).inDays;
          final key = d <= 0 ? 'Later today' : d == 1 ? 'Tomorrow' : d < 7 ? 'This week' : 'Later';
          groups.putIfAbsent(key, () => []).add(r);
        }

        return Scaffold(
          floatingActionButton: FloatingActionButton.extended(
            onPressed: () => _openEditor(),
            icon: const Icon(Icons.add_rounded, size: 28),
            label: const Text('New reminder', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w600)),
          ),
          body: SafeArea(
            child: !state.loaded
                ? const Center(child: CircularProgressIndicator())
                : CustomScrollView(
                    slivers: [
                      SliverToBoxAdapter(
                        child: Padding(
                          padding: const EdgeInsets.fromLTRB(20, 16, 8, 8),
                          child: Row(
                            children: [
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(DateFormat('EEEE, d MMMM').format(DateTime.now()),
                                        style: theme.textTheme.titleSmall?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
                                    const SizedBox(height: 2),
                                    Text(_greeting,
                                        style: theme.textTheme.headlineMedium?.copyWith(fontWeight: FontWeight.w800)),
                                  ],
                                ),
                              ),
                              IconButton(
                                tooltip: 'History',
                                iconSize: 28,
                                onPressed: _openHistory,
                                icon: Badge(
                                  isLabelVisible: state.unseenMissed > 0,
                                  label: Text('${state.unseenMissed}'),
                                  child: const Icon(Icons.history_rounded),
                                ),
                              ),
                              IconButton(
                                tooltip: 'Settings',
                                iconSize: 28,
                                onPressed: () => Navigator.of(context)
                                    .push(MaterialPageRoute(builder: (_) => const SettingsScreen())),
                                icon: Badge(
                                  isLabelVisible: state.missingCritical.isNotEmpty,
                                  child: const Icon(Icons.settings_rounded),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                      if (state.missingCritical.isNotEmpty)
                        _pad(NoticeCard(
                          icon: Icons.warning_amber_rounded,
                          color: const Color(0xFFE5484D),
                          title: 'Alerts may not show',
                          message: 'Remindly needs a couple of permissions to ring on time and show full screen.',
                          action: 'Fix now',
                          onTap: () => Navigator.of(context)
                              .push(MaterialPageRoute(builder: (_) => const SettingsScreen(focusReliability: true))),
                        )),
                      if (state.unseenMissed > 0)
                        _pad(NoticeCard(
                          icon: Icons.notification_important_rounded,
                          color: const Color(0xFFF76B15),
                          title: 'You missed ${state.unseenMissed} reminder${state.unseenMissed == 1 ? '' : 's'}',
                          message: 'Tap to see what they were.',
                          action: 'View',
                          onTap: _openHistory,
                        )),
                      if (state.reminders.isEmpty)
                        SliverToBoxAdapter(child: _EmptyState(onTemplate: (t) => _openEditor(null, t)))
                      else ...[
                        if (upcoming.isNotEmpty) ...[
                          _header(context, 'Next up'),
                          _pad(NextUpCard(reminder: upcoming.first, onTap: () => _openEditor(upcoming.first))),
                        ],
                        for (final e in groups.entries) ...[
                          _header(context, e.key),
                          _list(e.value),
                        ],
                        if (inactive.isNotEmpty) ...[
                          _header(context, 'Paused & completed'),
                          _list(inactive),
                        ],
                      ],
                      const SliverToBoxAdapter(child: SizedBox(height: 110)),
                    ],
                  ),
          ),
        );
      },
    );
  }

  Widget _pad(Widget child) =>
      SliverToBoxAdapter(child: Padding(padding: const EdgeInsets.fromLTRB(16, 8, 16, 8), child: child));

  Widget _header(BuildContext context, String text) => SliverToBoxAdapter(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(22, 18, 16, 6),
          child: Text(text,
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  )),
        ),
      );

  Widget _list(List<Reminder> items) => SliverPadding(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        sliver: SliverList.separated(
          itemCount: items.length,
          separatorBuilder: (_, _) => const SizedBox(height: 10),
          itemBuilder: (context, i) {
            final r = items[i];
            return Dismissible(
              key: ValueKey('r${r.id}'),
              direction: DismissDirection.endToStart,
              background: Container(
                alignment: Alignment.centerRight,
                padding: const EdgeInsets.only(right: 24),
                decoration: BoxDecoration(color: const Color(0xFFE5484D), borderRadius: BorderRadius.circular(20)),
                child: const Icon(Icons.delete_rounded, color: Colors.white, size: 28),
              ),
              onDismissed: (_) => _delete(r),
              child: ReminderTile(
                reminder: r,
                onTap: () => _openEditor(r),
                onToggle: (v) => state.setEnabled(r, v),
              ),
            );
          },
        ),
      );
}

class _EmptyState extends StatelessWidget {
  final ValueChanged<Template> onTemplate;
  const _EmptyState({required this.onTemplate});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 32, 20, 0),
      child: Column(
        children: [
          Container(
            width: 120,
            height: 120,
            decoration: BoxDecoration(color: theme.colorScheme.primaryContainer, shape: BoxShape.circle),
            child: Icon(Icons.alarm_add_rounded, size: 60, color: theme.colorScheme.onPrimaryContainer),
          ),
          const SizedBox(height: 20),
          Text('No reminders yet', style: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700)),
          const SizedBox(height: 6),
          Text('Pick one to start, or tap "New reminder".',
              textAlign: TextAlign.center, style: theme.textTheme.bodyLarge),
          const SizedBox(height: 20),
          Wrap(
            spacing: 10,
            runSpacing: 10,
            alignment: WrapAlignment.center,
            children: [for (final t in templates.take(8)) TemplateChip(template: t, onTap: () => onTemplate(t))],
          ),
        ],
      ),
    );
  }
}

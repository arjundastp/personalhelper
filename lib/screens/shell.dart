import 'package:material_ui/material_ui.dart';

import '../sprint/review_screen.dart';
import '../sprint/sprint_screen.dart';
import '../sprint/sprint_state.dart';
import '../state.dart';
import '../team/team_screen.dart';
import '../team/team_state.dart';
import 'home_screen.dart';
import 'landing_screen.dart';

/// Top level. With no extras it is just the reminders list; each extra added in Settings
/// (Daily Sprint, Team summary) adds an item to a bottom menu, which then starts with Home.
class Shell extends StatefulWidget {
  const Shell({super.key});

  @override
  State<Shell> createState() => _ShellState();
}

class _ShellState extends State<Shell> {
  final app = AppState.instance;
  final sprint = SprintState.instance;
  final team = TeamState.instance;
  late String tab = _startTab();

  List<String> get _tabs {
    final extras = [if (sprint.enabled) 'sprint', if (team.enabled) 'team'];
    return extras.isEmpty ? ['reminders'] : ['home', 'reminders', ...extras];
  }

  /// Which menu opens first: Settings › Display › "Open app on".
  String _startTab() {
    var want = app.setting<Object>('startTab', 'home').toString();
    if (want == 'last') {
      final last = app.settings['lastTab'];
      want = last is String ? last : (last == 1 ? 'sprint' : 'reminders'); // older versions stored an index
    }
    return _tabs.contains(want) ? want : _tabs.first;
  }

  void _select(String key) {
    setState(() => tab = key);
    if (key == 'team') team.markSeen();
    if (app.setting('startTab', 'home') == 'last') app.updateSettings({'lastTab': key});
  }

  @override
  void initState() {
    super.initState();
    app.addListener(_handleOpen);
    sprint.addListener(_onExtras);
    team.addListener(_onExtras);
    WidgetsBinding.instance.addPostFrameCallback((_) => _handleOpen());
  }

  @override
  void dispose() {
    app.removeListener(_handleOpen);
    sprint.removeListener(_onExtras);
    team.removeListener(_onExtras);
    super.dispose();
  }

  void _onExtras() {
    if (!mounted) return;
    setState(() {
      if (!_tabs.contains(tab)) tab = _tabs.first;
    });
    // A new summary arrived while the Teams tab is on screen: it has been seen.
    if (tab == 'team' && WidgetsBinding.instance.lifecycleState == AppLifecycleState.resumed) {
      WidgetsBinding.instance.addPostFrameCallback((_) => team.markSeen());
    }
  }

  /// A Daily Sprint notification or the evening alert asked to open a screen.
  void _handleOpen() {
    final action = app.pendingOpen;
    if (action == null || !mounted) return;
    if (action == 'team') {
      if (!team.enabled) return;
      app.pendingOpen = null;
      Navigator.of(context).popUntil((r) => r.isFirst);
      _select('team');
      return;
    }
    if (!sprint.enabled) return;
    app.pendingOpen = null;
    final nav = Navigator.of(context);
    nav.popUntil((r) => r.isFirst);
    _select('sprint');
    if (action == 'sprintReview') {
      nav.push(MaterialPageRoute(builder: (_) => ReviewScreen(date: sprint.today)));
    }
  }

  /// The bottom bar shows at most [_maxSlots] items. With more menus, the last slot becomes "More",
  /// which lists the rest (new menus go there, so the bar stays the same).
  static const _maxSlots = 4;

  ({IconData icon, IconData selected, String label}) _info(String t) => switch (t) {
    'home' => (icon: Icons.home_outlined, selected: Icons.home_rounded, label: 'Home'),
    'sprint' => (icon: Icons.assignment_outlined, selected: Icons.assignment_turned_in_rounded, label: 'Sprint'),
    'team' => (icon: Icons.forum_outlined, selected: Icons.forum_rounded, label: 'Teams'),
    _ => (icon: Icons.notifications_none_rounded, selected: Icons.notifications_rounded, label: 'Reminders'),
  };

  /// Full names, used in the More list.
  String _title(String t) => switch (t) {
    'home' => 'Home',
    'sprint' => 'Daily Sprint',
    'team' => 'Team summary',
    _ => 'Reminders',
  };

  Future<void> _openMore(List<String> rest) async {
    final picked = await showModalBottomSheet<String>(
      context: context,
      builder: (c) => SafeArea(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          const Padding(
            padding: EdgeInsets.fromLTRB(24, 0, 24, 6),
            child: Align(alignment: Alignment.centerLeft, child: Text('More', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w600))),
          ),
          for (final t in rest)
            ListTile(
              leading: Icon(t == tab ? _info(t).selected : _info(t).icon),
              title: Text(_title(t)),
              selected: t == tab,
              onTap: () => Navigator.pop(c, t),
            ),
          const SizedBox(height: 6),
        ]),
      ),
    );
    if (picked != null) _select(picked);
  }

  Widget _icon(String t, bool selected, int open) {
    final icon = Icon(selected ? _info(t).selected : _info(t).icon);
    return t == 'sprint' ? Badge(isLabelVisible: open > 0, label: Text('$open'), child: icon) : icon;
  }

  @override
  Widget build(BuildContext context) {
    final tabs = _tabs;
    if (tabs.length == 1) return const HomeScreen();
    final index = tabs.indexOf(tab).clamp(0, tabs.length - 1);
    final open = sprint.openToday();
    return Scaffold(
      body: IndexedStack(index: index, children: [
        for (final t in tabs)
          switch (t) {
            'sprint' => const SprintScreen(),
            'team' => const TeamScreen(),
            'home' => LandingScreen(onOpenTab: _select),
            _ => const HomeScreen(),
          },
      ]),
      bottomNavigationBar: Builder(builder: (context) {
        final overflow = tabs.length > _maxSlots;
        final shown = overflow ? tabs.take(_maxSlots - 1).toList() : tabs;
        final rest = overflow ? tabs.skip(_maxSlots - 1).toList() : const <String>[];
        final selected = shown.contains(tab) ? shown.indexOf(tab) : shown.length; // "More" holds the rest
        final mq = MediaQuery.of(context);
        // Keep the bar tidy with "Bigger text": labels grow a little, never wrap or overflow.
        return MediaQuery(
          data: mq.copyWith(textScaler: mq.textScaler.clamp(maxScaleFactor: 1.1)),
          child: NavigationBar(
            selectedIndex: selected,
            labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
            onDestinationSelected: (i) => i < shown.length ? _select(shown[i]) : _openMore(rest),
            destinations: [
              for (final t in shown)
                NavigationDestination(icon: _icon(t, false, open), selectedIcon: _icon(t, true, open), label: _info(t).label, tooltip: _title(t)),
              if (overflow)
                NavigationDestination(
                  icon: Badge(isLabelVisible: rest.contains('sprint') && open > 0, child: const Icon(Icons.more_horiz_rounded)),
                  label: 'More',
                ),
            ],
          ),
        );
      }),
    );
  }
}

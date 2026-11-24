import 'package:material_ui/material_ui.dart';

import '../sprint/review_screen.dart';
import '../sprint/sprint_screen.dart';
import '../sprint/sprint_state.dart';
import '../state.dart';
import '../team/team_screen.dart';
import '../team/team_state.dart';
import 'home_screen.dart';

/// Top level. With no extras it is just the reminders list; each extra added in Settings
/// (Daily Sprint, Team summary) adds an item to a bottom menu.
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

  List<String> get _tabs => ['reminders', if (sprint.enabled) 'sprint', if (team.enabled) 'team'];

  /// Which menu opens first: Settings › Display › "Open app on".
  String _startTab() {
    var want = app.setting<Object>('startTab', 'reminders').toString();
    if (want == 'last') {
      final last = app.settings['lastTab'];
      want = last is String ? last : (last == 1 ? 'sprint' : 'reminders'); // older versions stored an index
    }
    return _tabs.contains(want) ? want : 'reminders';
  }

  void _select(String key) {
    setState(() => tab = key);
    if (app.setting('startTab', 'reminders') == 'last') app.updateSettings({'lastTab': key});
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
      if (!_tabs.contains(tab)) tab = 'reminders';
    });
  }

  /// A Daily Sprint notification or the evening alert asked to open a screen.
  void _handleOpen() {
    final action = app.pendingOpen;
    if (action == null || !mounted || !sprint.enabled) return;
    app.pendingOpen = null;
    final nav = Navigator.of(context);
    nav.popUntil((r) => r.isFirst);
    _select('sprint');
    if (action == 'sprintReview') {
      nav.push(MaterialPageRoute(builder: (_) => ReviewScreen(date: sprint.today)));
    }
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
            _ => const HomeScreen(),
          },
      ]),
      bottomNavigationBar: NavigationBar(
        selectedIndex: index,
        onDestinationSelected: (i) => _select(tabs[i]),
        destinations: [
          for (final t in tabs)
            switch (t) {
              'sprint' => NavigationDestination(
                  icon: Badge(isLabelVisible: open > 0, label: Text('$open'), child: const Icon(Icons.assignment_outlined)),
                  selectedIcon:
                      Badge(isLabelVisible: open > 0, label: Text('$open'), child: const Icon(Icons.assignment_turned_in_rounded)),
                  label: 'Daily Sprint',
                ),
              'team' => const NavigationDestination(
                  icon: Icon(Icons.forum_outlined),
                  selectedIcon: Icon(Icons.forum_rounded),
                  label: 'Team summary',
                ),
              _ => const NavigationDestination(
                  icon: Icon(Icons.notifications_none_rounded),
                  selectedIcon: Icon(Icons.notifications_rounded),
                  label: 'Reminders',
                ),
            },
        ],
      ),
    );
  }
}

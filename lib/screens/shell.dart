import 'package:material_ui/material_ui.dart';

import '../sprint/review_screen.dart';
import '../sprint/sprint_screen.dart';
import '../sprint/sprint_state.dart';
import '../state.dart';
import 'home_screen.dart';

/// Top level. Without Daily Sprint it is just the reminders list; once Daily Sprint is added
/// in Settings, a bottom menu appears: Reminders | Daily Sprint.
class Shell extends StatefulWidget {
  const Shell({super.key});

  @override
  State<Shell> createState() => _ShellState();
}

class _ShellState extends State<Shell> {
  final app = AppState.instance;
  final sprint = SprintState.instance;
  int tab = 0;

  @override
  void initState() {
    super.initState();
    app.addListener(_handleOpen);
    sprint.addListener(_onSprint);
    WidgetsBinding.instance.addPostFrameCallback((_) => _handleOpen());
  }

  @override
  void dispose() {
    app.removeListener(_handleOpen);
    sprint.removeListener(_onSprint);
    super.dispose();
  }

  void _onSprint() {
    if (!mounted) return;
    setState(() {
      if (!sprint.enabled) tab = 0;
    });
  }

  /// A Daily Sprint notification or the evening alert asked to open a screen.
  void _handleOpen() {
    final action = app.pendingOpen;
    if (action == null || !mounted || !sprint.enabled) return;
    app.pendingOpen = null;
    final nav = Navigator.of(context);
    nav.popUntil((r) => r.isFirst);
    setState(() => tab = 1);
    if (action == 'sprintReview') {
      nav.push(MaterialPageRoute(builder: (_) => ReviewScreen(date: sprint.today)));
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!sprint.enabled) return const HomeScreen();
    final open = sprint.openToday();
    return Scaffold(
      body: IndexedStack(index: tab, children: const [HomeScreen(), SprintScreen()]),
      bottomNavigationBar: NavigationBar(
        selectedIndex: tab,
        onDestinationSelected: (i) => setState(() => tab = i),
        destinations: [
          const NavigationDestination(
            icon: Icon(Icons.notifications_none_rounded),
            selectedIcon: Icon(Icons.notifications_rounded),
            label: 'Reminders',
          ),
          NavigationDestination(
            icon: Badge(isLabelVisible: open > 0, label: Text('$open'), child: const Icon(Icons.assignment_outlined)),
            selectedIcon: Badge(isLabelVisible: open > 0, label: Text('$open'), child: const Icon(Icons.assignment_turned_in_rounded)),
            label: 'Daily Sprint',
          ),
        ],
      ),
    );
  }
}

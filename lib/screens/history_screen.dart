import 'package:material_ui/material_ui.dart';

import '../format.dart';
import '../native.dart';
import '../state.dart';
import '../widgets.dart';

class HistoryScreen extends StatefulWidget {
  const HistoryScreen({super.key});

  @override
  State<HistoryScreen> createState() => _HistoryScreenState();
}

class _HistoryScreenState extends State<HistoryScreen> {
  final state = AppState.instance;
  late final Set<int> _unseenAtOpen;

  @override
  void initState() {
    super.initState();
    // Remember which ones were new so they stay highlighted while the screen is open.
    _unseenAtOpen = {
      for (var i = 0; i < state.history.length; i++)
        if (!state.history[i].seen) i,
    };
    Native.markHistorySeen().then((_) => state.refresh());
  }

  static const _status = {
    'done': ('Done', Icons.check_circle_rounded, Color(0xFF30A46C)),
    'snoozed': ('Snoozed', Icons.snooze_rounded, Color(0xFF0D74CE)),
    'auto_snoozed': ('No answer – will ring again', Icons.replay_rounded, Color(0xFFF76B15)),
    'missed': ('Missed', Icons.error_rounded, Color(0xFFE5484D)),
  };

  Future<void> _clear() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('Clear history?'),
        content: const Text('This only clears the list below. Your reminders are not changed.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(c, true), child: const Text('Clear')),
        ],
      ),
    );
    if (ok == true) {
      await Native.clearHistory();
      await state.refresh();
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return ListenableBuilder(
      listenable: state,
      builder: (context, _) {
        final items = state.history;
        return Scaffold(
          appBar: AppBar(
            title: const Text('History', style: TextStyle(fontWeight: FontWeight.w700)),
            actions: [
              if (items.isNotEmpty)
                IconButton(tooltip: 'Clear history', onPressed: _clear, icon: const Icon(Icons.delete_sweep_rounded)),
            ],
          ),
          body: items.isEmpty
              ? Center(
                  child: Column(mainAxisSize: MainAxisSize.min, children: [
                    Icon(Icons.history_toggle_off_rounded, size: 72, color: theme.colorScheme.outline),
                    const SizedBox(height: 12),
                    Text('Nothing here yet', style: theme.textTheme.titleMedium),
                    const SizedBox(height: 4),
                    const Text('Reminders you dismiss, snooze or miss appear here.'),
                  ]),
                )
              : ListView.separated(
                  padding: const EdgeInsets.all(16),
                  itemCount: items.length,
                  separatorBuilder: (_, _) => const SizedBox(height: 10),
                  itemBuilder: (context, i) {
                    final h = items[i];
                    final (label, icon, color) = _status[h.status] ?? _status['done']!;
                    final isNew = _unseenAtOpen.contains(i);
                    return Card(
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(20),
                        side: isNew ? BorderSide(color: color, width: 2) : BorderSide.none,
                      ),
                      child: Padding(
                        padding: const EdgeInsets.all(14),
                        child: Row(children: [
                          CategoryAvatar(category: h.category, size: 48),
                          const SizedBox(width: 14),
                          Expanded(
                            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                              Text(h.title, style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700)),
                              const SizedBox(height: 2),
                              Text('Due ${fmtWhen(context, h.dueAt)}', style: theme.textTheme.bodyMedium),
                              const SizedBox(height: 4),
                              Row(children: [
                                Icon(icon, size: 18, color: color),
                                const SizedBox(width: 4),
                                Flexible(
                                  child: Text(label, style: TextStyle(color: color, fontWeight: FontWeight.w600)),
                                ),
                              ]),
                            ]),
                          ),
                        ]),
                      ),
                    );
                  },
                ),
        );
      },
    );
  }
}

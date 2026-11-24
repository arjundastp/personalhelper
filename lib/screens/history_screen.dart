import 'package:material_ui/material_ui.dart';

import '../format.dart';
import '../main.dart' show AppColors;
import '../native.dart';
import '../state.dart';
import '../widgets.dart';

/// What happened to each alert, laid out like a phone's call log.
class HistoryScreen extends StatefulWidget {
  const HistoryScreen({super.key});

  @override
  State<HistoryScreen> createState() => _HistoryScreenState();
}

class _HistoryScreenState extends State<HistoryScreen> {
  final state = AppState.instance;

  @override
  void initState() {
    super.initState();
    Native.markHistorySeen().then((_) => state.refresh());
  }

  static const _status = {
    'done': ('Done', Icons.check_circle_rounded, AppColors.accent),
    'snoozed': ('Reminded later', Icons.snooze_rounded, Color(0xFF0D74CE)),
    'auto_snoozed': ('No answer, rang again', Icons.replay_rounded, Color(0xFFF76B15)),
    'missed': ('Missed', Icons.cancel_rounded, AppColors.red),
  };

  Future<void> _clear() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('Clear history?'),
        content: const Text('Your reminders will not change.', style: TextStyle(fontSize: 14.5)),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Cancel')),
          TextButton(onPressed: () => Navigator.pop(c, true), child: const Text('Clear')),
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
    final grey = Theme.of(context).colorScheme.onSurfaceVariant;
    return ListenableBuilder(
      listenable: state,
      builder: (context, _) {
        final items = state.history;
        return Scaffold(
          appBar: AppBar(
            title: const Text('History'),
            actions: [
              if (items.isNotEmpty)
                PopupMenuButton<String>(
                  onSelected: (_) => _clear(),
                  itemBuilder: (_) => const [
                    PopupMenuItem(value: 'clear', child: Text('Clear history', style: TextStyle(fontSize: 14.5))),
                  ],
                ),
            ],
          ),
          body: items.isEmpty
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(32),
                    child: Column(mainAxisSize: MainAxisSize.min, children: [
                      Icon(Icons.history_rounded, size: 72, color: grey.withValues(alpha: 0.5)),
                      const SizedBox(height: 12),
                      const Text('Nothing here yet', style: TextStyle(fontSize: 17.5, fontWeight: FontWeight.w600)),
                      const SizedBox(height: 6),
                      Text('When a reminder rings, you will see it here.',
                          textAlign: TextAlign.center, style: TextStyle(fontSize: 14.5, color: grey)),
                    ]),
                  ),
                )
              : ListView.separated(
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  itemCount: items.length,
                  separatorBuilder: (_, _) => const Divider(indent: 74),
                  itemBuilder: (context, i) {
                    final h = items[i];
                    final (label, icon, color) = _status[h.status] ?? _status['done']!;
                    return Padding(
                      padding: const EdgeInsets.fromLTRB(16, 9, 16, 9),
                      child: Row(children: [
                        CategoryAvatar(category: h.category),
                        const SizedBox(width: 16),
                        Expanded(
                          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                            Text(h.title,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  fontSize: 15.5,
                                  fontWeight: FontWeight.w600,
                                  color: h.status == 'missed' ? AppColors.red : null,
                                )),
                            const SizedBox(height: 4),
                            Row(children: [
                              Icon(icon, size: 17, color: color),
                              const SizedBox(width: 5),
                              Flexible(child: Text(label, style: TextStyle(fontSize: 13.5, color: grey))),
                            ]),
                          ]),
                        ),
                        const SizedBox(width: 8),
                        Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
                          Text(fmtTime(context, h.dueAt), style: TextStyle(fontSize: 13, color: grey)),
                          const SizedBox(height: 4),
                          Text(fmtDay(h.dueAt), style: TextStyle(fontSize: 13, color: grey)),
                        ]),
                      ]),
                    );
                  },
                ),
        );
      },
    );
  }
}

import 'package:intl/intl.dart';
import 'package:material_ui/material_ui.dart';

import '../main.dart' show AppColors;
import '../widgets.dart';
import 'sprint_screen.dart' show SprintComposer, sprintBlue, editTextDialog;
import 'sprint_state.dart';

/// The "Parked" tab: paused tasks wait here with no alerts until brought back to a day.
class ParkedView extends StatefulWidget {
  const ParkedView({super.key});

  @override
  State<ParkedView> createState() => _ParkedViewState();
}

class _ParkedViewState extends State<ParkedView> with AutomaticKeepAliveClientMixin {
  final sprint = SprintState.instance;
  final input = TextEditingController();
  final focus = FocusNode();

  @override
  bool get wantKeepAlive => true;

  @override
  void dispose() {
    input.dispose();
    focus.dispose();
    super.dispose();
  }

  void _toast(String text) {
    final m = ScaffoldMessenger.of(context);
    m.clearSnackBars();
    m.showSnackBar(SnackBar(content: Text(text)));
  }

  Future<void> _menu(ParkedTask p) async {
    final choice = await showModalBottomSheet<String>(
      context: context,
      builder: (c) => SafeArea(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(24, 0, 24, 4),
            child: Text(p.text, style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w600)),
          ),
          OptionRow(icon: Icons.today_outlined, title: 'Add to today', onTap: () => Navigator.pop(c, 'today')),
          OptionRow(icon: Icons.edit_outlined, title: 'Change text', onTap: () => Navigator.pop(c, 'edit')),
          OptionRow(icon: Icons.check_circle_outline_rounded, title: 'Already done – remove', onTap: () => Navigator.pop(c, 'done')),
          OptionRow(icon: Icons.delete_outline_rounded, title: 'Delete', color: AppColors.red, onTap: () => Navigator.pop(c, 'delete')),
          const SizedBox(height: 6),
        ]),
      ),
    );
    if (!mounted) return;
    switch (choice) {
      case 'today':
        await sprint.bringBack(p.id);
        _toast('Added to today');
      case 'edit':
        final text = await editTextDialog(context, title: 'Change task', initial: p.text);
        if (text != null && text.trim().isNotEmpty) await sprint.update((s) => p.text = text.trim());
      case 'done':
        await sprint.removeParked(p.id);
        _toast('Removed. Nice work!');
      case 'delete':
        await sprint.removeParked(p.id);
        _toast('Deleted');
    }
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final theme = Theme.of(context);
    final grey = theme.colorScheme.onSurfaceVariant;
    return ListenableBuilder(
      listenable: sprint,
      builder: (context, _) {
        final items = sprint.parked;
        return Column(children: [
          Expanded(
            child: items.isEmpty
                ? Center(
                    child: Padding(
                      padding: const EdgeInsets.all(32),
                      child: Column(mainAxisSize: MainAxisSize.min, children: [
                        Icon(Icons.inventory_2_outlined, size: 48, color: grey.withValues(alpha: 0.45)),
                        const SizedBox(height: 10),
                        Text('Nothing parked.\nPaused tasks wait here, with no alerts.',
                            textAlign: TextAlign.center, style: TextStyle(fontSize: 14.5, color: grey, height: 1.4)),
                      ]),
                    ),
                  )
                : ListView(
                    padding: const EdgeInsets.only(top: 4, bottom: 12),
                    children: [
                      Padding(
                        padding: const EdgeInsets.fromLTRB(20, 8, 20, 4),
                        child: Text('${items.length} waiting · no alerts until you bring them back',
                            style: TextStyle(fontSize: 12.5, color: grey)),
                      ),
                      for (final p in items)
                        InkWell(
                          onTap: () => _menu(p),
                          onLongPress: () => _menu(p),
                          child: Container(
                            padding: const EdgeInsets.fromLTRB(16, 8, 10, 8),
                            decoration: BoxDecoration(border: Border(bottom: BorderSide(color: theme.colorScheme.outlineVariant))),
                            child: Row(children: [
                              Container(
                                width: 32,
                                height: 32,
                                decoration: BoxDecoration(color: sprintBlue.withValues(alpha: 0.12), shape: BoxShape.circle),
                                child: const Icon(Icons.pause_rounded, size: 17, color: sprintBlue),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                                  Text(p.text, style: const TextStyle(fontSize: 15)),
                                  Text(
                                    p.pausedOn == sprint.today
                                        ? 'Parked today'
                                        : 'Paused ${DateFormat('d MMM').format(DateTime.parse(p.pausedOn))}',
                                    style: TextStyle(fontSize: 12, color: grey),
                                  ),
                                ]),
                              ),
                              TextButton.icon(
                                style: TextButton.styleFrom(
                                  visualDensity: VisualDensity.compact,
                                  textStyle: TextStyle(
                                    fontFamily: theme.textTheme.bodyMedium?.fontFamily,
                                    fontSize: 13,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                                onPressed: () async {
                                  await sprint.bringBack(p.id);
                                  _toast('Added to today');
                                },
                                icon: const Icon(Icons.north_west_rounded, size: 16),
                                label: const Text('Today'),
                              ),
                            ]),
                          ),
                        ),
                    ],
                  ),
          ),
          SprintComposer(
            controller: input,
            focus: focus,
            hint: 'Park an idea for later',
            sendLabel: 'Park task',
            onSend: () {
              final t = input.text;
              input.clear();
              sprint.park(t);
            },
          ),
        ]);
      },
    );
  }
}

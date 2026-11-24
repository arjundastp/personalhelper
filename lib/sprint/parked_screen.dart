import 'package:intl/intl.dart';
import 'package:material_ui/material_ui.dart';

import '../main.dart' show AppColors;
import '../widgets.dart';
import 'sprint_screen.dart' show SprintComposer, sprintBlue, editTextDialog;
import 'sprint_state.dart';

/// Paused / parked tasks: they wait here with no alerts until brought back to a day.
class ParkedScreen extends StatefulWidget {
  const ParkedScreen({super.key});

  @override
  State<ParkedScreen> createState() => _ParkedScreenState();
}

class _ParkedScreenState extends State<ParkedScreen> {
  final sprint = SprintState.instance;
  final input = TextEditingController();
  final focus = FocusNode();

  @override
  void dispose() {
    input.dispose();
    focus.dispose();
    super.dispose();
  }

  void _toast(String text) {
    final m = ScaffoldMessenger.of(context);
    m.clearSnackBars();
    m.showSnackBar(SnackBar(content: Text(text, style: const TextStyle(fontSize: 16))));
  }

  Future<void> _menu(ParkedTask p) async {
    final choice = await showModalBottomSheet<String>(
      context: context,
      builder: (c) => SafeArea(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(24, 0, 24, 8),
            child: Text(p.text, style: const TextStyle(fontSize: 19, fontWeight: FontWeight.w600)),
          ),
          OptionRow(icon: Icons.today_rounded, title: 'Add to today', onTap: () => Navigator.pop(c, 'today')),
          OptionRow(icon: Icons.edit_rounded, title: 'Change text', onTap: () => Navigator.pop(c, 'edit')),
          OptionRow(icon: Icons.check_circle_outline_rounded, title: 'Already done – remove', onTap: () => Navigator.pop(c, 'done')),
          OptionRow(icon: Icons.delete_rounded, title: 'Delete', color: AppColors.red, onTap: () => Navigator.pop(c, 'delete')),
          const SizedBox(height: 8),
        ]),
      ),
    );
    if (!mounted) return;
    switch (choice) {
      case 'today':
        await sprint.bringBack(p.id);
        _toast('"${p.text}" added to today');
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
    final theme = Theme.of(context);
    final grey = theme.colorScheme.onSurfaceVariant;
    return ListenableBuilder(
      listenable: sprint,
      builder: (context, _) {
        final items = sprint.parked;
        return Scaffold(
          appBar: AppBar(title: const Text('Parked tasks')),
          body: Column(children: [
            Expanded(
              child: ListView(
                padding: const EdgeInsets.only(bottom: 16),
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(20, 16, 20, 4),
                    child: Text(
                      'Tasks you paused. They wait here, with no alerts, until you bring them back to a day.',
                      style: TextStyle(fontSize: 15, color: grey, height: 1.4),
                    ),
                  ),
                  if (items.isNotEmpty) ListHeader('${items.length} task${items.length == 1 ? '' : 's'} waiting'),
                  if (items.isEmpty)
                    Padding(
                      padding: const EdgeInsets.fromLTRB(32, 48, 32, 0),
                      child: Column(children: [
                        Icon(Icons.inventory_2_outlined, size: 60, color: grey.withValues(alpha: 0.5)),
                        const SizedBox(height: 12),
                        Text('Nothing parked.\nPaused tasks will show up here.',
                            textAlign: TextAlign.center, style: TextStyle(fontSize: 16, color: grey)),
                      ]),
                    ),
                  for (final p in items)
                    InkWell(
                      onTap: () => _menu(p),
                      onLongPress: () => _menu(p),
                      child: Container(
                        padding: const EdgeInsets.fromLTRB(20, 12, 16, 12),
                        decoration: BoxDecoration(border: Border(bottom: BorderSide(color: theme.colorScheme.outlineVariant))),
                        child: Row(children: [
                          Expanded(
                            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                              Text(p.text, style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w600)),
                              const SizedBox(height: 3),
                              Row(children: [
                                const Icon(Icons.pause_rounded, size: 16, color: sprintBlue),
                                const SizedBox(width: 4),
                                Flexible(
                                  child: Text(
                                    p.pausedOn == sprint.today
                                        ? 'Parked today'
                                        : 'Paused ${DateFormat('d MMM').format(DateTime.parse(p.pausedOn))}',
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: TextStyle(fontSize: 14, color: grey),
                                  ),
                                ),
                              ]),
                            ]),
                          ),
                          const SizedBox(width: 10),
                          OutlinedButton(
                            style: OutlinedButton.styleFrom(
                              minimumSize: const Size(0, 44),
                              padding: const EdgeInsets.symmetric(horizontal: 14),
                              side: const BorderSide(color: AppColors.accent, width: 1.5),
                              textStyle: TextStyle(
                                fontFamily: theme.textTheme.bodyMedium?.fontFamily,
                                fontSize: 15,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            onPressed: () async {
                              await sprint.bringBack(p.id);
                              _toast('"${p.text}" added to today');
                            },
                            child: const Text('Add to today'),
                          ),
                        ]),
                      ),
                    ),
                  if (items.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.fromLTRB(24, 14, 24, 0),
                      child: Text('Tap a task to change it, mark it done or delete it.',
                          textAlign: TextAlign.center, style: TextStyle(fontSize: 13.5, color: grey)),
                    ),
                ],
              ),
            ),
            SprintComposer(
              controller: input,
              focus: focus,
              hint: 'Park a task for later…',
              sendLabel: 'Park task',
              onSend: () {
                final t = input.text;
                input.clear();
                sprint.park(t);
              },
            ),
          ]),
        );
      },
    );
  }
}

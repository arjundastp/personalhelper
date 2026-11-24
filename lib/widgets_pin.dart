import 'package:material_ui/material_ui.dart';

import 'native.dart';

/// "Add widget to home screen": asks the launcher to place the DayMate widget; if the launcher
/// can't, explains how to add it by hand.
Future<void> addHomeWidget(BuildContext context) async {
  final ok = await Native.pinWidget().catchError((_) => false);
  if (!context.mounted) return;
  if (ok) {
    ScaffoldMessenger.of(context)
      ..clearSnackBars()
      ..showSnackBar(const SnackBar(content: Text('Confirm on the next screen to add the widget.')));
    return;
  }
  await showDialog<void>(
    context: context,
    builder: (c) => AlertDialog(
      title: const Text('Add the DayMate widget', style: TextStyle(fontSize: 18)),
      content: const Text(
        '1. Touch and hold an empty spot on your home screen.\n'
        '2. Tap Widgets.\n'
        '3. Find DayMate, then drag the widget to your home screen.',
        style: TextStyle(fontSize: 15, height: 1.5),
      ),
      actions: [TextButton(onPressed: () => Navigator.pop(c), child: const Text('OK'))],
    ),
  );
}

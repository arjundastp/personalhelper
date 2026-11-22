import 'package:material_ui/material_ui.dart';

import 'format.dart';
import 'main.dart' show AppColors;
import 'models.dart';

/// Round coloured icon, like a contact photo.
class CategoryAvatar extends StatelessWidget {
  final String category;
  final double size;
  final bool muted;
  const CategoryAvatar({super.key, required this.category, this.size = 54, this.muted = false});

  @override
  Widget build(BuildContext context) {
    final c = categoryOf(category);
    final color = muted ? Theme.of(context).colorScheme.onSurfaceVariant : c.color;
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(color: color.withValues(alpha: 0.15), shape: BoxShape.circle),
      child: Icon(c.icon, color: color, size: size * 0.5),
    );
  }
}

/// One reminder in the main list, laid out like a chat row:
/// round icon · name + how it repeats · time on the right.
class ReminderRow extends StatelessWidget {
  final Reminder reminder;
  final VoidCallback onTap;
  final VoidCallback onLongPress;
  const ReminderRow({super.key, required this.reminder, required this.onTap, required this.onLongPress});

  @override
  Widget build(BuildContext context) {
    final r = reminder;
    final theme = Theme.of(context);
    final grey = theme.colorScheme.onSurfaceVariant;
    final next = r.nextAlert;
    final on = r.enabled && next != null;
    final snoozed = on && r.snoozedUntil != null && r.snoozedUntil == next;
    final soon = on && next.difference(DateTime.now()).inHours < 24;
    final green = theme.brightness == Brightness.light ? AppColors.green : AppColors.accent;

    return InkWell(
      onTap: onTap,
      onLongPress: onLongPress,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
        child: Row(
          children: [
            CategoryAvatar(category: r.category, muted: !on),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: Text(
                          r.title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 17.5,
                            fontWeight: FontWeight.w600,
                            color: on ? theme.colorScheme.onSurface : grey,
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Text(
                        on ? fmtTime(context, next) : '',
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: soon ? FontWeight.w600 : FontWeight.w400,
                          color: snoozed ? const Color(0xFFF76B15) : (soon ? green : grey),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Row(
                    children: [
                      Icon(
                        snoozed
                            ? Icons.snooze_rounded
                            : (r.repeat.type == 'once' ? Icons.event_outlined : Icons.repeat_rounded),
                        size: 17,
                        color: snoozed ? const Color(0xFFF76B15) : grey,
                      ),
                      const SizedBox(width: 5),
                      Expanded(
                        child: Text(
                          snoozed ? 'Snoozed' : (on ? repeatSummary(context, r) : _offText(r)),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(fontSize: 15, color: grey),
                        ),
                      ),
                      const SizedBox(width: 8),
                      if (on)
                        Text(fmtDay(next), style: TextStyle(fontSize: 13, color: grey))
                      else
                        _Pill(text: r.repeat.type == 'once' && r.lastFired != null ? 'Done' : 'Off'),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _offText(Reminder r) => r.repeat.type == 'once' && r.lastFired != null
      ? 'Finished · ${fmtDay(r.startDate)}'
      : 'Turned off';
}

class _Pill extends StatelessWidget {
  final String text;
  const _Pill({required this.text});

  @override
  Widget build(BuildContext context) {
    final grey = Theme.of(context).colorScheme.onSurfaceVariant;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 2),
      decoration: BoxDecoration(color: grey.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(20)),
      child: Text(text, style: TextStyle(fontSize: 13, color: grey, fontWeight: FontWeight.w600)),
    );
  }
}

/// Small green section title ("Today", "Later" …).
class ListHeader extends StatelessWidget {
  final String text;
  const ListHeader(this.text, {super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 18, 20, 4),
      child: Text(
        text,
        style: TextStyle(
          fontSize: 15,
          fontWeight: FontWeight.w600,
          color: theme.brightness == Brightness.light ? AppColors.green : AppColors.accent,
        ),
      ),
    );
  }
}

/// A settings-style row: grey icon, title, optional grey value underneath.
class OptionRow extends StatelessWidget {
  final IconData icon;
  final String title;
  final String? value;
  final VoidCallback? onTap;
  final Widget? trailing;
  final Color? color;
  const OptionRow({super.key, required this.icon, required this.title, this.value, this.onTap, this.trailing, this.color});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return InkWell(
      onTap: onTap,
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: 68),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
          child: Row(
            children: [
              Icon(icon, size: 26, color: color ?? theme.colorScheme.onSurfaceVariant),
              const SizedBox(width: 24),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(title, style: TextStyle(fontSize: 17, color: color ?? theme.colorScheme.onSurface)),
                    if (value != null) ...[
                      const SizedBox(height: 2),
                      Text(value!, style: TextStyle(fontSize: 15, color: theme.colorScheme.onSurfaceVariant)),
                    ],
                  ],
                ),
              ),
              ?trailing,
            ],
          ),
        ),
      ),
    );
  }
}

/// Grey band that separates groups of rows, like in a phone's settings.
class GroupGap extends StatelessWidget {
  final String? title;
  const GroupGap({super.key, this.title});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(height: 8, color: theme.colorScheme.outlineVariant.withValues(alpha: 0.6)),
        if (title != null) ListHeader(title!),
      ],
    );
  }
}

/// Bottom sheet with a simple list of choices; returns the chosen value.
Future<T?> chooseOne<T>(
  BuildContext context, {
  required String title,
  required List<(T, String)> options,
  required T current,
}) {
  return showModalBottomSheet<T>(
    context: context,
    isScrollControlled: true,
    builder: (c) => SafeArea(
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 0, 24, 8),
              child: Text(title, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w600)),
            ),
            for (final (value, label) in options)
              RadioRow(label: label, selected: value == current, onTap: () => Navigator.pop(c, value)),
            const SizedBox(height: 12),
          ],
        ),
      ),
    ),
  );
}

/// A big radio-button row.
class RadioRow extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;
  const RadioRow({super.key, required this.label, required this.selected, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final grey = Theme.of(context).colorScheme.onSurfaceVariant;
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
        child: Row(children: [
          Icon(selected ? Icons.radio_button_checked_rounded : Icons.radio_button_off_rounded,
              color: selected ? AppColors.accent : grey, size: 26),
          const SizedBox(width: 20),
          Expanded(child: Text(label, style: const TextStyle(fontSize: 17))),
        ]),
      ),
    );
  }
}


/// Round day buttons M T W T F S S.
class DayPicker extends StatelessWidget {
  final Set<int> selected;
  final ValueChanged<int> onToggle;
  const DayPicker({super.key, required this.selected, required this.onToggle});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        for (var d = 1; d <= 7; d++)
          Semantics(
            label: weekdayShort[d - 1],
            selected: selected.contains(d),
            button: true,
            child: InkWell(
              customBorder: const CircleBorder(),
              onTap: () => onToggle(d),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 150),
                width: 42,
                height: 42,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: selected.contains(d) ? AppColors.accent : theme.colorScheme.outlineVariant,
                ),
                child: Text(
                  weekdayLetter[d - 1],
                  style: TextStyle(
                    fontSize: 17,
                    fontWeight: FontWeight.w700,
                    color: selected.contains(d) ? Colors.white : theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }
}

/// Simple tinted banner row shown at the top of the list.
class BannerRow extends StatelessWidget {
  final IconData icon;
  final Color color;
  final String title;
  final String subtitle;
  final VoidCallback onTap;
  const BannerRow({super.key, required this.icon, required this.color, required this.title, required this.subtitle, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Material(
      color: color.withValues(alpha: 0.10),
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 14, 12, 14),
          child: Row(children: [
            Container(
              width: 54,
              height: 54,
              decoration: BoxDecoration(color: color.withValues(alpha: 0.18), shape: BoxShape.circle),
              child: Icon(icon, color: color, size: 28),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(title, style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w600)),
                const SizedBox(height: 2),
                Text(subtitle, style: TextStyle(fontSize: 15, color: Theme.of(context).colorScheme.onSurfaceVariant)),
              ]),
            ),
            Icon(Icons.chevron_right_rounded, color: color),
          ]),
        ),
      ),
    );
  }
}

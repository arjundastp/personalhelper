import 'package:material_ui/material_ui.dart';

import 'format.dart';
import 'models.dart';

class CategoryAvatar extends StatelessWidget {
  final String category;
  final double size;
  final bool muted;
  const CategoryAvatar({super.key, required this.category, this.size = 52, this.muted = false});

  @override
  Widget build(BuildContext context) {
    final c = categoryOf(category);
    final color = muted ? Theme.of(context).colorScheme.outline : c.color;
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(color: color.withValues(alpha: 0.14), borderRadius: BorderRadius.circular(size * 0.32)),
      child: Icon(c.icon, color: color, size: size * 0.52),
    );
  }
}

class ReminderTile extends StatelessWidget {
  final Reminder reminder;
  final VoidCallback onTap;
  final ValueChanged<bool> onToggle;
  const ReminderTile({super.key, required this.reminder, required this.onTap, required this.onToggle});

  @override
  Widget build(BuildContext context) {
    final r = reminder;
    final theme = Theme.of(context);
    final active = r.enabled && r.nextAlert != null;
    final next = r.nextAlert;
    final snoozed = r.snoozedUntil != null && r.snoozedUntil == next;
    final muted = theme.colorScheme.onSurfaceVariant;
    return Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(14, 14, 8, 14),
          child: Row(
            children: [
              CategoryAvatar(category: r.category, muted: !active),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(r.title,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.w700,
                          color: active ? null : muted,
                        )),
                    const SizedBox(height: 4),
                    Text(
                      active
                          ? (snoozed ? 'Snoozed until ${fmtTime(context, next!)}' : fmtWhen(context, next!))
                          : (r.repeat.type == 'once' && r.lastFired != null ? 'Done' : 'Paused'),
                      style: theme.textTheme.bodyLarge?.copyWith(
                        fontWeight: FontWeight.w600,
                        color: snoozed ? const Color(0xFFF76B15) : (active ? theme.colorScheme.primary : muted),
                      ),
                    ),
                    const SizedBox(height: 2),
                    Row(
                      children: [
                        Icon(r.repeat.type == 'once' ? Icons.event_rounded : Icons.repeat_rounded, size: 16, color: muted),
                        const SizedBox(width: 4),
                        Expanded(
                          child: Text(repeatSummary(context, r),
                              maxLines: 1, overflow: TextOverflow.ellipsis, style: theme.textTheme.bodyMedium?.copyWith(color: muted)),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              Switch(value: r.enabled, onChanged: onToggle),
            ],
          ),
        ),
      ),
    );
  }
}

class NextUpCard extends StatelessWidget {
  final Reminder reminder;
  final VoidCallback onTap;
  const NextUpCard({super.key, required this.reminder, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final r = reminder;
    final c = categoryOf(r.category);
    final next = r.nextAlert!;
    return Material(
      borderRadius: BorderRadius.circular(24),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Ink(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: [c.color, Color.lerp(c.color, Colors.black, 0.25)!],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
          ),
          padding: const EdgeInsets.all(20),
          child: Row(
            children: [
              Container(
                width: 64,
                height: 64,
                decoration: BoxDecoration(color: Colors.white.withValues(alpha: 0.2), shape: BoxShape.circle),
                child: Icon(c.icon, color: Colors.white, size: 34),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(r.title,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.w700)),
                    const SizedBox(height: 6),
                    Text(fmtWhen(context, next),
                        style: const TextStyle(color: Colors.white, fontSize: 17, fontWeight: FontWeight.w600)),
                    const SizedBox(height: 2),
                    Text(fmtRelative(next), style: TextStyle(color: Colors.white.withValues(alpha: 0.85), fontSize: 15)),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class NoticeCard extends StatelessWidget {
  final IconData icon;
  final Color color;
  final String title;
  final String message;
  final String action;
  final VoidCallback onTap;
  const NoticeCard({
    super.key,
    required this.icon,
    required this.color,
    required this.title,
    required this.message,
    required this.action,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Material(
      color: color.withValues(alpha: 0.12),
      borderRadius: BorderRadius.circular(20),
      child: InkWell(
        borderRadius: BorderRadius.circular(20),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              Icon(icon, color: color, size: 32),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title, style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700)),
                    const SizedBox(height: 2),
                    Text(message, style: theme.textTheme.bodyMedium),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Text(action, style: TextStyle(color: color, fontWeight: FontWeight.w700, fontSize: 16)),
            ],
          ),
        ),
      ),
    );
  }
}

class TemplateChip extends StatelessWidget {
  final Template template;
  final VoidCallback onTap;
  final bool selected;
  const TemplateChip({super.key, required this.template, required this.onTap, this.selected = false});

  @override
  Widget build(BuildContext context) {
    final c = categoryOf(template.category);
    return ActionChip(
      avatar: Icon(c.icon, color: c.color, size: 20),
      label: Text(template.label, style: const TextStyle(fontSize: 15)),
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 8),
      backgroundColor: selected ? c.color.withValues(alpha: 0.15) : null,
      side: BorderSide(color: selected ? c.color : c.color.withValues(alpha: 0.3)),
      onPressed: onTap,
    );
  }
}

/// Section title + rounded card holding a group of rows.
class Section extends StatelessWidget {
  final String title;
  final List<Widget> children;
  final Widget? trailing;
  const Section({super.key, required this.title, required this.children, this.trailing});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(6, 20, 6, 8),
          child: Row(
            children: [
              Expanded(
                child: Text(title,
                    style: theme.textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.w700,
                      color: theme.colorScheme.primary,
                      letterSpacing: 0.3,
                    )),
              ),
              ?trailing,
            ],
          ),
        ),
        Card(clipBehavior: Clip.antiAlias, child: Column(children: children)),
      ],
    );
  }
}

/// A big, easy to hit row: icon, label, value, chevron.
class BigTile extends StatelessWidget {
  final IconData icon;
  final String label;
  final String? value;
  final VoidCallback? onTap;
  final Widget? trailing;
  final Color? iconColor;
  const BigTile({super.key, required this.icon, required this.label, this.value, this.onTap, this.trailing, this.iconColor});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return InkWell(
      onTap: onTap,
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: 64),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          child: Row(
            children: [
              Icon(icon, color: iconColor ?? theme.colorScheme.primary, size: 26),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(label, style: theme.textTheme.titleMedium),
                    if (value != null)
                      Text(value!, style: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
                  ],
                ),
              ),
              trailing ?? (onTap != null ? Icon(Icons.chevron_right_rounded, color: theme.colorScheme.outline) : const SizedBox()),
            ],
          ),
        ),
      ),
    );
  }
}

/// [-]  value  [+] stepper with large touch targets.
class Stepper2 extends StatelessWidget {
  final int value;
  final int min;
  final int max;
  final String Function(int) label;
  final ValueChanged<int> onChanged;
  const Stepper2({super.key, required this.value, this.min = 1, this.max = 99, required this.label, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Row(
      children: [
        IconButton.filledTonal(
          iconSize: 26,
          onPressed: value > min ? () => onChanged(value - 1) : null,
          icon: const Icon(Icons.remove_rounded),
        ),
        Expanded(
          child: Text(label(value),
              textAlign: TextAlign.center, style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700)),
        ),
        IconButton.filledTonal(
          iconSize: 26,
          onPressed: value < max ? () => onChanged(value + 1) : null,
          icon: const Icon(Icons.add_rounded),
        ),
      ],
    );
  }
}

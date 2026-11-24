import 'dart:math' as math;

import 'package:intl/intl.dart' hide TextDirection;
import 'package:material_ui/material_ui.dart';

import '../format.dart' show fmtDay;
import '../models.dart' show isoDate;
import 'sprint_state.dart';
import 'sprint_stats.dart';

/// Status colours for charts. Validated (dataviz validator) for colour-blind separation and
/// lightness in both modes; "not updated" is a neutral track, not a series colour.
class SprintColors {
  final Color done, notDone, paused, track, card, ink, muted;
  final List<Color> heat; // sequential ramp, low -> high completion
  final Color heatNone;
  const SprintColors._(this.done, this.notDone, this.paused, this.track, this.card, this.ink, this.muted, this.heat, this.heatNone);

  static SprintColors of(BuildContext context) {
    final light = Theme.of(context).brightness == Brightness.light;
    final cs = Theme.of(context).colorScheme;
    return light
        ? SprintColors._(
            const Color(0xFF00A884), const Color(0xFFE5773A), const Color(0xFF3E63DD), const Color(0xFFE3E7EA),
            const Color(0xFFF5F7F8), cs.onSurface, cs.onSurfaceVariant,
            const [Color(0xFFD3F0E6), Color(0xFF96DCC4), Color(0xFF3FBF98), Color(0xFF00876A)],
            const Color(0xFFECEFF1),
          )
        : SprintColors._(
            const Color(0xFF1BAE86), const Color(0xFFD26A33), const Color(0xFF6E8CF0), const Color(0xFF2A3942),
            const Color(0xFF1A262D), cs.onSurface, cs.onSurfaceVariant,
            const [Color(0xFF173C33), Color(0xFF1C6150), Color(0xFF1F8A6D), Color(0xFF34C59C)],
            const Color(0xFF202D35),
          );
  }

  Color get leave => const Color(0xFFB39DDB);

  Color heatFor(double? rate) {
    if (rate == null) return heatNone;
    if (rate < 0.25) return heat[0];
    if (rate < 0.5) return heat[1];
    if (rate < 0.75) return heat[2];
    return heat[3];
  }
}

/// The "Insights" tab: a small dashboard of how planned work actually went.
class InsightsView extends StatefulWidget {
  const InsightsView({super.key});

  @override
  State<InsightsView> createState() => _InsightsViewState();
}

class _InsightsViewState extends State<InsightsView> {
  final sprint = SprintState.instance;
  int days = 7;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: sprint,
      builder: (context, _) {
        final c = SprintColors.of(context);
        final st = SprintStats(sprint, days: days);
        if (sprint.tasks.isEmpty) {
          return _Empty(color: c.muted);
        }
        final totals = st.totals;
        final delta = st.completionDelta;
        return ListView(
          padding: const EdgeInsets.fromLTRB(14, 12, 14, 24),
          children: [
            Row(children: [
              Expanded(
                child: Text(days == 7 ? 'Last 7 days' : 'Last 30 days',
                    style: TextStyle(fontSize: 13, color: c.muted, fontWeight: FontWeight.w500)),
              ),
              SegmentedButton<int>(
                showSelectedIcon: false,
                style: ButtonStyle(
                  visualDensity: const VisualDensity(horizontal: -3, vertical: -3),
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  textStyle: WidgetStatePropertyAll(TextStyle(
                    fontFamily: DefaultTextStyle.of(context).style.fontFamily,
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                  )),
                ),
                segments: const [
                  ButtonSegment(value: 7, label: Text('7 days')),
                  ButtonSegment(value: 30, label: Text('30 days')),
                ],
                selected: {days},
                onSelectionChanged: (v) => setState(() => days = v.first),
              ),
            ]),
            const SizedBox(height: 10),

            // ---- headline numbers ----
            GridView.count(
              crossAxisCount: 2,
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              mainAxisSpacing: 8,
              crossAxisSpacing: 8,
              childAspectRatio: 2.05,
              children: [
                _StatTile(
                  label: 'Completed',
                  value: st.completion == null ? '–' : '${st.completion}%',
                  note: delta == null ? 'of planned tasks' : '${delta.abs()} pts vs previous',
                  noteIcon: delta == null ? null : (delta >= 0 ? Icons.arrow_upward_rounded : Icons.arrow_downward_rounded),
                  noteColor: delta == null ? null : (delta >= 0 ? c.done : c.notDone),
                ),
                _StatTile(label: 'Tasks done', value: '${totals.done}', note: 'of ${totals.total} planned'),
                _StatTile(label: 'Streak', value: '${sprint.streak}', note: sprint.streak == 1 ? 'day fully updated' : 'days fully updated'),
                _StatTile(label: 'Parked', value: '${sprint.parked.length}', note: 'paused tasks waiting'),
              ],
            ),

            // ---- daily progress ----
            _Card(
              title: 'Daily progress',
              subtitle: 'Tap a bar to see the day',
              child: _DailyChart(data: st.daily, colors: c),
            ),

            // ---- how tasks ended ----
            _Card(
              title: 'How tasks ended',
              subtitle: '${totals.total} task${totals.total == 1 ? '' : 's'} on ${st.plannedDays} planned day${st.plannedDays == 1 ? '' : 's'}',
              child: _EndedBar(totals: totals, colors: c),
            ),

            // ---- calendar heatmap ----
            _Card(
              title: 'Activity calendar',
              subtitle: 'Last 5 weeks · darker = more of the plan done',
              child: _Heatmap(weeks: st.heatmap(), colors: c, leaveOf: (d) => sprint.leaveOn(isoDate(d))),
            ),

            // ---- attendance ----
            _Card(
              title: 'Work days & leave',
              subtitle: 'Half-day leave counts as 0.5',
              child: _AttendanceTable(
                columns: [
                  (days == 7 ? '7 days' : '30 days', st.windowAttendance),
                  (DateFormat('MMM').format(DateTime.now()), st.monthAttendance),
                  ('${DateTime.now().year}', st.yearAttendance),
                ],
                colors: c,
              ),
            ),

            // ---- best weekdays ----
            _Card(
              title: 'Best days of the week',
              subtitle: 'Share of planned tasks done · last 8 weeks',
              child: _WeekdayBars(rates: st.weekdayRates, colors: c, workdays: sprint.workdays.toSet()),
            ),

            // ---- slipping ----
            if (st.slipping.isNotEmpty)
              _Card(
                title: 'Tasks that keep slipping',
                subtitle: 'Marked "Not done" on 2+ days. Try splitting them or parking them.',
                child: Column(children: [
                  for (final t in st.slipping)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 5),
                      child: Row(children: [
                        Icon(Icons.replay_rounded, size: 18, color: c.notDone),
                        const SizedBox(width: 10),
                        Expanded(child: Text(t.text, style: TextStyle(fontSize: 14, color: c.ink))),
                        Text('${t.timesNotDone}×', style: TextStyle(fontSize: 13, color: c.muted, fontWeight: FontWeight.w600)),
                      ]),
                    ),
                ]),
              ),
          ],
        );
      },
    );
  }
}

class _Empty extends StatelessWidget {
  final Color color;
  const _Empty({required this.color});

  @override
  Widget build(BuildContext context) => Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Icon(Icons.insights_rounded, size: 52, color: color.withValues(alpha: 0.5)),
            const SizedBox(height: 10),
            Text('Charts appear here once you plan and update a few days.',
                textAlign: TextAlign.center, style: TextStyle(fontSize: 14.5, color: color)),
          ]),
        ),
      );
}

class _Card extends StatelessWidget {
  final String title;
  final String? subtitle;
  final Widget child;
  const _Card({required this.title, this.subtitle, required this.child});

  @override
  Widget build(BuildContext context) {
    final c = SprintColors.of(context);
    return Container(
      margin: const EdgeInsets.only(top: 10),
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 14),
      decoration: BoxDecoration(color: c.card, borderRadius: BorderRadius.circular(16)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(title, style: TextStyle(fontSize: 14.5, fontWeight: FontWeight.w600, color: c.ink)),
        if (subtitle != null)
          Padding(
            padding: const EdgeInsets.only(top: 2),
            child: Text(subtitle!, style: TextStyle(fontSize: 12, color: c.muted)),
          ),
        const SizedBox(height: 12),
        child,
      ]),
    );
  }
}

class _StatTile extends StatelessWidget {
  final String label, value, note;
  final Color? noteColor;
  final IconData? noteIcon;
  const _StatTile({required this.label, required this.value, required this.note, this.noteColor, this.noteIcon});

  @override
  Widget build(BuildContext context) {
    final c = SprintColors.of(context);
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 9, 12, 9),
      decoration: BoxDecoration(color: c.card, borderRadius: BorderRadius.circular(14)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisAlignment: MainAxisAlignment.center, children: [
        Text(label, style: TextStyle(fontSize: 12, color: c.muted)),
        Text(value, style: TextStyle(fontSize: 21, fontWeight: FontWeight.w600, color: c.ink, height: 1.25)),
        Row(children: [
          if (noteIcon != null) Icon(noteIcon, size: 13, color: noteColor ?? c.muted),
          Expanded(
            child: Text(note,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(fontSize: 11.5, color: noteColor ?? c.muted, fontWeight: noteColor == null ? null : FontWeight.w600)),
          ),
        ]),
      ]),
    );
  }
}

class _Legend extends StatelessWidget {
  final List<(Color, String)> items;
  const _Legend(this.items);

  @override
  Widget build(BuildContext context) {
    final c = SprintColors.of(context);
    return Wrap(spacing: 12, runSpacing: 4, children: [
      for (final (color, label) in items)
        Row(mainAxisSize: MainAxisSize.min, children: [
          Container(width: 9, height: 9, decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(2))),
          const SizedBox(width: 5),
          Text(label, style: TextStyle(fontSize: 12, color: c.muted)),
        ]),
    ]);
  }
}

// ------------------------------------------------------------------ daily stacked columns

class _DailyChart extends StatefulWidget {
  final List<DayCounts> data;
  final SprintColors colors;
  const _DailyChart({required this.data, required this.colors});

  @override
  State<_DailyChart> createState() => _DailyChartState();
}

class _DailyChartState extends State<_DailyChart> {
  int? selected;

  @override
  void didUpdateWidget(covariant _DailyChart old) {
    super.didUpdateWidget(old);
    if (old.data.length != widget.data.length) selected = null;
  }

  @override
  Widget build(BuildContext context) {
    final c = widget.colors;
    final data = widget.data;
    final sel = selected == null ? data.last : data[selected!];
    String detail(DayCounts d) {
      if (d.total == 0) return '${fmtDay(d.day)} · nothing planned';
      final parts = [
        '${d.done} done',
        if (d.notDone > 0) '${d.notDone} not done',
        if (d.paused > 0) '${d.paused} paused',
        if (d.open > 0) '${d.open} not updated',
      ];
      return '${fmtDay(d.day)} · ${parts.join(' · ')}';
    }

    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      _Legend([(c.done, 'Done'), (c.notDone, 'Not done'), (c.paused, 'Paused'), (c.track, 'Not updated')]),
      const SizedBox(height: 10),
      LayoutBuilder(builder: (context, box) {
        const height = 132.0;
        return Semantics(
          label: 'Daily progress chart. ${data.where((d) => d.total > 0).map(detail).join('. ')}',
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTapDown: (e) {
              final slot = box.maxWidth / data.length;
              setState(() => selected = (e.localPosition.dx / slot).floor().clamp(0, data.length - 1));
            },
            child: CustomPaint(
              size: Size(box.maxWidth, height + 20),
              painter: _DailyPainter(
                data: data,
                colors: c,
                selected: selected ?? data.length - 1,
                surface: c.card,
                labelStyle: TextStyle(fontFamily: DefaultTextStyle.of(context).style.fontFamily, fontSize: 10.5, color: c.muted),
                selectedLabelStyle: TextStyle(
                  fontFamily: DefaultTextStyle.of(context).style.fontFamily,
                  fontSize: 10.5,
                  color: c.ink,
                  fontWeight: FontWeight.w700,
                ),
                chartHeight: height,
              ),
            ),
          ),
        );
      }),
      const SizedBox(height: 6),
      Text(detail(sel), style: TextStyle(fontSize: 12.5, color: c.ink, fontWeight: FontWeight.w500)),
    ]);
  }
}

class _DailyPainter extends CustomPainter {
  final List<DayCounts> data;
  final SprintColors colors;
  final int selected;
  final Color surface;
  final TextStyle labelStyle, selectedLabelStyle;
  final double chartHeight;
  _DailyPainter({
    required this.data,
    required this.colors,
    required this.selected,
    required this.surface,
    required this.labelStyle,
    required this.selectedLabelStyle,
    required this.chartHeight,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final maxTotal = math.max(1, data.map((d) => d.total).fold<int>(0, math.max));
    final top = _niceMax(maxTotal);
    final grid = Paint()
      ..color = colors.track
      ..strokeWidth = 1;
    // Recessive hairline gridlines: baseline, middle, top.
    for (final f in [0.0, 0.5, 1.0]) {
      final y = chartHeight - chartHeight * f;
      canvas.drawLine(Offset(0, y), Offset(size.width, y), grid);
    }
    final topLabel = TextPainter(text: TextSpan(text: '$top', style: labelStyle), textDirection: TextDirection.ltr)..layout();
    topLabel.paint(canvas, Offset(size.width - topLabel.width, -topLabel.height - 1 < 0 ? 0 : -topLabel.height - 1));

    final slot = size.width / data.length;
    final barW = math.min(22.0, slot * (data.length > 10 ? 0.7 : 0.55));
    for (var i = 0; i < data.length; i++) {
      final d = data[i];
      final x = slot * i + (slot - barW) / 2;
      if (i == selected) {
        canvas.drawRRect(
          RRect.fromRectAndRadius(Rect.fromLTWH(slot * i + 1, 0, slot - 2, chartHeight), const Radius.circular(6)),
          Paint()..color = colors.track.withValues(alpha: 0.45),
        );
      }
      if (d.total > 0) {
        final unit = chartHeight / top;
        var y = chartHeight;
        final segs = [(d.done, colors.done), (d.notDone, colors.notDone), (d.paused, colors.paused), (d.open, colors.track)]
            .where((s) => s.$1 > 0)
            .toList();
        for (var k = 0; k < segs.length; k++) {
          final h = segs[k].$1 * unit;
          final isTop = k == segs.length - 1;
          // 2px surface gap between stacked segments.
          final segH = math.max(1.0, isTop ? h : h - 2);
          final r = Rect.fromLTWH(x, y - h + (isTop ? 0 : 2), barW, segH);
          canvas.drawRRect(
            RRect.fromRectAndCorners(
              r,
              topLeft: isTop ? const Radius.circular(4) : Radius.zero,
              topRight: isTop ? const Radius.circular(4) : Radius.zero,
            ),
            Paint()..color = segs[k].$2,
          );
          y -= h;
        }
      }
      // x labels: every day for 7, weekly for 30 (plus the selected one).
      final showLabel = data.length <= 10 || i == data.length - 1 || (data.length - 1 - i) % 7 == 0 || i == selected;
      if (showLabel) {
        final text = data.length <= 10 ? DateFormat('E').format(d.day).substring(0, 2) : DateFormat('d/M').format(d.day);
        final tp = TextPainter(
          text: TextSpan(text: text, style: i == selected ? selectedLabelStyle : labelStyle),
          textDirection: TextDirection.ltr,
        )..layout();
        final lx = (slot * i + slot / 2 - tp.width / 2).clamp(0.0, size.width - tp.width);
        tp.paint(canvas, Offset(lx, chartHeight + 5));
      }
    }
  }

  int _niceMax(int v) {
    if (v <= 4) return 4;
    if (v <= 6) return 6;
    if (v <= 8) return 8;
    if (v <= 10) return 10;
    return ((v + 4) ~/ 5) * 5;
  }

  @override
  bool shouldRepaint(covariant _DailyPainter old) => old.data != data || old.selected != selected || old.colors != colors;
}

// ------------------------------------------------------------------ one-whole segmented bar

class _EndedBar extends StatelessWidget {
  final DayCounts totals;
  final SprintColors colors;
  const _EndedBar({required this.totals, required this.colors});

  @override
  Widget build(BuildContext context) {
    final c = colors;
    final t = totals;
    if (t.total == 0) return Text('Nothing planned in this period.', style: TextStyle(fontSize: 13, color: c.muted));
    final parts = [
      (t.done, c.done, 'Done'),
      (t.notDone, c.notDone, 'Not done'),
      (t.paused, c.paused, 'Paused'),
      (t.open, c.track, 'Not updated'),
    ].where((p) => p.$1 > 0).toList();
    String pct(int n) => '${(n * 100 / t.total).round()}%';
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Semantics(
        label: parts.map((p) => '${p.$3} ${p.$1}, ${pct(p.$1)}').join('; '),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(5),
          child: SizedBox(
            height: 14,
            child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              for (var i = 0; i < parts.length; i++) ...[
                if (i > 0) SizedBox(width: 2, child: ColoredBox(color: c.card)),
                Expanded(flex: parts[i].$1, child: ColoredBox(color: parts[i].$2)),
              ],
            ]),
          ),
        ),
      ),
      const SizedBox(height: 10),
      Wrap(spacing: 14, runSpacing: 6, children: [
        for (final p in parts)
          Row(mainAxisSize: MainAxisSize.min, children: [
            Container(width: 9, height: 9, decoration: BoxDecoration(color: p.$2, borderRadius: BorderRadius.circular(2))),
            const SizedBox(width: 5),
            Text('${p.$3} ', style: TextStyle(fontSize: 12.5, color: c.muted)),
            Text('${p.$1} · ${pct(p.$1)}', style: TextStyle(fontSize: 12.5, color: c.ink, fontWeight: FontWeight.w600)),
          ]),
      ]),
    ]);
  }
}

// ------------------------------------------------------------------ calendar heatmap

class _Heatmap extends StatefulWidget {
  final List<List<DayCounts?>> weeks;
  final SprintColors colors;
  final LeaveDay? Function(DateTime day) leaveOf;
  const _Heatmap({required this.weeks, required this.colors, required this.leaveOf});

  @override
  State<_Heatmap> createState() => _HeatmapState();
}

class _HeatmapState extends State<_Heatmap> {
  DayCounts? selected;

  @override
  Widget build(BuildContext context) {
    final c = widget.colors;
    const letters = ['M', 'T', 'W', 'T', 'F', 'S', 'S'];
    final today = DateTime.now();
    Color inkOn(Color fill) => fill.computeLuminance() > 0.4 ? const Color(0xFF111B21) : Colors.white;
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Row(children: [
        for (final l in letters)
          Expanded(child: Center(child: Text(l, style: TextStyle(fontSize: 11, color: c.muted, fontWeight: FontWeight.w600)))),
      ]),
      const SizedBox(height: 4),
      for (final week in widget.weeks)
        Padding(
          padding: const EdgeInsets.only(bottom: 4),
          child: Row(children: [
            for (final d in week)
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 2),
                  child: d == null
                      ? const SizedBox(height: 30)
                      : Semantics(
                          button: true,
                          label: '${DateFormat('EEEE d MMMM').format(d.day)}: '
                              '${d.total == 0 ? 'nothing planned' : '${d.done} of ${d.total} done'}',
                          child: InkWell(
                            borderRadius: BorderRadius.circular(7),
                            onTap: () => setState(() => selected = d),
                            child: Container(
                              height: 30,
                              alignment: Alignment.center,
                              decoration: BoxDecoration(
                                color: widget.leaveOf(d.day)?.fullDayOff == true ? c.leave : c.heatFor(d.rate),
                                borderRadius: BorderRadius.circular(7),
                                border: DateUtils.isSameDay(d.day, today) || identical(d, selected)
                                    ? Border.all(color: c.ink, width: 1.5)
                                    : null,
                              ),
                              child: Text(
                                '${d.day.day}',
                                style: TextStyle(
                                  fontSize: 11.5,
                                  fontWeight: FontWeight.w600,
                                  color: widget.leaveOf(d.day)?.fullDayOff == true
                                      ? const Color(0xFF111B21)
                                      : (d.rate == null ? c.muted : inkOn(c.heatFor(d.rate))),
                                ),
                              ),
                            ),
                          ),
                        ),
                ),
              ),
          ]),
        ),
      const SizedBox(height: 6),
      Row(children: [
        Text('Less', style: TextStyle(fontSize: 11.5, color: c.muted)),
        const SizedBox(width: 6),
        for (final h in c.heat)
          Container(
            width: 14,
            height: 14,
            margin: const EdgeInsets.only(right: 3),
            decoration: BoxDecoration(color: h, borderRadius: BorderRadius.circular(3)),
          ),
        const SizedBox(width: 3),
        Text('More', style: TextStyle(fontSize: 11.5, color: c.muted)),
        const Spacer(),
        Container(width: 14, height: 14, decoration: BoxDecoration(color: c.leave, borderRadius: BorderRadius.circular(3))),
        const SizedBox(width: 5),
        Text('Leave', style: TextStyle(fontSize: 11.5, color: c.muted)),
        const SizedBox(width: 10),
        Container(width: 14, height: 14, decoration: BoxDecoration(color: c.heatNone, borderRadius: BorderRadius.circular(3))),
        const SizedBox(width: 5),
        Text('No plan', style: TextStyle(fontSize: 11.5, color: c.muted)),
      ]),
      if (selected != null) ...[
        const SizedBox(height: 8),
        Text(
          '${fmtDay(selected!.day)} · '
          '${selected!.total == 0 ? 'nothing planned' : '${selected!.done} of ${selected!.total} done (${(selected!.rate! * 100).round()}%)'}',
          style: TextStyle(fontSize: 12.5, color: c.ink, fontWeight: FontWeight.w500),
        ),
      ],
    ]);
  }
}

// ------------------------------------------------------------------ weekday bars

class _WeekdayBars extends StatelessWidget {
  final Map<int, double?> rates;
  final SprintColors colors;
  final Set<int> workdays;
  const _WeekdayBars({required this.rates, required this.colors, required this.workdays});

  @override
  Widget build(BuildContext context) {
    final c = colors;
    const names = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
    final shown = [for (var w = 1; w <= 7; w++) if (workdays.contains(w) || rates[w] != null) w];
    final best = shown.where((w) => rates[w] != null).fold<int?>(null, (b, w) => b == null || rates[w]! > rates[b]! ? w : b);
    return Column(children: [
      for (final w in shown)
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 3),
          child: Row(children: [
            SizedBox(
              width: 36,
              child: Text(names[w - 1],
                  style: TextStyle(fontSize: 12.5, color: w == best ? c.ink : c.muted, fontWeight: w == best ? FontWeight.w700 : null)),
            ),
            Expanded(
              child: LayoutBuilder(builder: (context, box) {
                final r = rates[w];
                return Stack(children: [
                  Container(height: 12, decoration: BoxDecoration(color: c.track, borderRadius: BorderRadius.circular(4))),
                  if (r != null && r > 0)
                    Container(
                      height: 12,
                      width: math.max(6, box.maxWidth * r),
                      decoration: BoxDecoration(color: c.done, borderRadius: BorderRadius.circular(4)),
                    ),
                ]);
              }),
            ),
            SizedBox(
              width: 44,
              child: Text(
                rates[w] == null ? '–' : '${(rates[w]! * 100).round()}%',
                textAlign: TextAlign.right,
                style: TextStyle(fontSize: 12.5, color: c.ink, fontWeight: w == best ? FontWeight.w700 : FontWeight.w500),
              ),
            ),
          ]),
        ),
      if (best != null)
        Padding(
          padding: const EdgeInsets.only(top: 6),
          child: Row(children: [
            Icon(Icons.emoji_events_outlined, size: 16, color: c.muted),
            const SizedBox(width: 6),
            Expanded(
              child: Text('Your strongest day is ${DateFormat('EEEE').format(DateTime(2024, 1, best))}.',
                  style: TextStyle(fontSize: 12.5, color: c.muted)),
            ),
          ]),
        ),
    ]);
  }
}

// ------------------------------------------------------------------ attendance table

class _AttendanceTable extends StatelessWidget {
  final List<(String, Attendance)> columns;
  final SprintColors colors;
  const _AttendanceTable({required this.columns, required this.colors});

  String _n(double v) => v == v.roundToDouble() ? v.toInt().toString() : v.toStringAsFixed(1);

  @override
  Widget build(BuildContext context) {
    final c = colors;
    final rows = <(String, String Function(Attendance))>[
      ('Working days', (a) => _n(a.workingDays)),
      ('Leave taken', (a) => _n(a.leaveDays)),
      ('Half days', (a) => '${a.halfDays}'),
      ('Holidays', (a) => '${a.holidays}'),
      ('Days reported', (a) => a.plannedDays == 0 ? '0' : '${a.reportedDays}/${a.plannedDays}'),
    ];
    TextStyle head = TextStyle(fontSize: 12, color: c.muted, fontWeight: FontWeight.w600);
    return Table(
      columnWidths: const {0: FlexColumnWidth(1.6)},
      defaultVerticalAlignment: TableCellVerticalAlignment.middle,
      children: [
        TableRow(children: [
          const SizedBox(),
          for (final col in columns) Padding(padding: const EdgeInsets.only(bottom: 6), child: Text(col.$1, textAlign: TextAlign.right, style: head)),
        ]),
        for (final (label, value) in rows)
          TableRow(
            decoration: BoxDecoration(border: Border(top: BorderSide(color: c.track))),
            children: [
              Padding(padding: const EdgeInsets.symmetric(vertical: 6), child: Text(label, style: TextStyle(fontSize: 13, color: c.ink))),
              for (final col in columns)
                Text(value(col.$2), textAlign: TextAlign.right, style: TextStyle(fontSize: 13.5, color: c.ink, fontWeight: FontWeight.w600)),
            ],
          ),
      ],
    );
  }
}

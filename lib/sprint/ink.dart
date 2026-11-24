import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:material_ui/material_ui.dart';

/// One pen stroke. Points are stored relative to the page width (x and y both divided by the
/// width), so handwriting keeps its shape on any screen size or orientation.
class InkStroke {
  /// Colour token: 'ink' (black in light mode, white in dark), 'blue', 'red', 'green', 'marker' (yellow highlighter).
  final String color;
  final double width; // relative to page width
  final List<Offset> points;
  final List<double> pressure; // 0..1 per point (1.0 for fingers)

  InkStroke({required this.color, required this.width, List<Offset>? points, List<double>? pressure}) : points = points ?? [], pressure = pressure ?? [];

  bool get isMarker => color == 'marker';

  Map<String, dynamic> toJson() => {
    'c': color,
    'w': _r(width),
    'p': [
      for (final o in points) ...[_r(o.dx), _r(o.dy)],
    ],
    'f': [for (final f in pressure) (f * 100).round()],
  };

  factory InkStroke.fromJson(Map<String, dynamic> j) {
    final p = (j['p'] as List?) ?? const [];
    final f = (j['f'] as List?) ?? const [];
    return InkStroke(
      color: j['c'] as String? ?? 'ink',
      width: (j['w'] as num?)?.toDouble() ?? 0.004,
      points: [for (var i = 0; i + 1 < p.length; i += 2) Offset((p[i] as num).toDouble(), (p[i + 1] as num).toDouble())],
      pressure: [for (final v in f) (v as num).toDouble() / 100],
    );
  }

  static double _r(double v) => (v * 10000).roundToDouble() / 10000;

  InkStroke _slice(int from, int to) =>
      InkStroke(color: color, width: width, points: points.sublist(from, to), pressure: pressure.length == points.length ? pressure.sublist(from, to) : null);
}

/// Erases everything within [radius] of [at] (page-relative units): strokes are cut where the eraser
/// passes, so only the touched part disappears. Returns null when nothing was touched.
List<InkStroke>? eraseAt(List<InkStroke> strokes, Offset at, double radius) {
  var changed = false;
  final out = <InkStroke>[];
  for (final s in strokes) {
    final reach = radius + s.width / 2;
    if (!s.points.any((p) => (p - at).distance <= reach)) {
      out.add(s);
      continue;
    }
    changed = true;
    var start = -1;
    for (var i = 0; i <= s.points.length; i++) {
      final keep = i < s.points.length && (s.points[i] - at).distance > reach;
      if (keep && start < 0) start = i;
      if (!keep && start >= 0) {
        if (i - start >= 2) out.add(s._slice(start, i)); // single dots left by a cut are dropped
        start = -1;
      }
    }
  }
  return changed ? out : null;
}

/// Colours for the tokens above, readable in both themes.
Color inkColor(String token, Brightness b) => switch (token) {
  'blue' => b == Brightness.light ? const Color(0xFF1A56DB) : const Color(0xFF7AA2FF),
  'red' => b == Brightness.light ? const Color(0xFFD93025) : const Color(0xFFFF8A80),
  'green' => b == Brightness.light ? const Color(0xFF00875A) : const Color(0xFF4FD1A5),
  'marker' => b == Brightness.light ? const Color(0x66FFD600) : const Color(0x80FFE066),
  _ => b == Brightness.light ? const Color(0xFF1B1B1F) : const Color(0xFFECEFF1),
};

/// Draws a list of strokes, scaled to the canvas width. Used for the editor and for thumbnails.
class InkPainter extends CustomPainter {
  final List<InkStroke> strokes;
  final InkStroke? live;
  final Brightness brightness;
  final bool lines; // ruled-paper lines
  final Color lineColor;
  final int version; // bump to repaint after in-place changes

  InkPainter({required this.strokes, this.live, required this.brightness, this.lines = false, this.lineColor = Colors.transparent, this.version = 0});

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    if (lines) {
      final p = Paint()
        ..color = lineColor
        ..strokeWidth = 1;
      final gap = w * 0.075;
      for (var y = gap * 1.5; y < size.height; y += gap) {
        canvas.drawLine(Offset(0, y), Offset(w, y), p);
      }
    }
    // Highlighter under the pen.
    for (final s in strokes.where((s) => s.isMarker)) {
      _stroke(canvas, s, w);
    }
    for (final s in strokes.where((s) => !s.isMarker)) {
      _stroke(canvas, s, w);
    }
    if (live != null) _stroke(canvas, live!, w);
  }

  void _stroke(Canvas canvas, InkStroke s, double w) {
    if (s.points.isEmpty) return;
    final color = inkColor(s.color, brightness);
    final base = s.width * w;
    final pts = [for (final p in s.points) p * w];
    if (pts.length == 1) {
      canvas.drawCircle(pts.first, base / 2, Paint()..color = color);
      return;
    }
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeCap = s.isMarker ? StrokeCap.square : StrokeCap.round
      ..strokeJoin = StrokeJoin.round;
    final hasPressure = s.pressure.length == s.points.length && !s.isMarker;
    if (!hasPressure) {
      final path = ui.Path()..moveTo(pts.first.dx, pts.first.dy);
      for (var i = 1; i < pts.length - 1; i++) {
        final mid = (pts[i] + pts[i + 1]) / 2;
        path.quadraticBezierTo(pts[i].dx, pts[i].dy, mid.dx, mid.dy);
      }
      path.lineTo(pts.last.dx, pts.last.dy);
      canvas.drawPath(path, paint..strokeWidth = base);
      return;
    }
    // Pressure: short smoothed segments, each with its own width.
    var prev = pts.first;
    for (var i = 1; i < pts.length; i++) {
      final next = i < pts.length - 1 ? (pts[i] + pts[i + 1]) / 2 : pts[i];
      final f = (s.pressure[i - 1] + s.pressure[i]) / 2;
      paint.strokeWidth = math.max(0.6, base * (0.45 + 0.9 * f));
      final path = ui.Path()
        ..moveTo(prev.dx, prev.dy)
        ..quadraticBezierTo(pts[i].dx, pts[i].dy, next.dx, next.dy);
      canvas.drawPath(path, paint);
      prev = next;
    }
  }

  @override
  bool shouldRepaint(InkPainter old) =>
      old.version != version || old.strokes != strokes || old.live != live || old.brightness != brightness || old.lines != lines;
}

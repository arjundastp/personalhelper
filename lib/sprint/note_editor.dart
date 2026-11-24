import 'dart:async';

import 'package:flutter/gestures.dart';
import 'package:intl/intl.dart';
import 'package:material_ui/material_ui.dart';

import '../format.dart' show fmtDay;
import '../main.dart' show AppColors;
import '../models.dart' show isoDate;
import 'ink.dart';
import 'notes_state.dart';

enum InkTool { pen, marker, eraser }

/// Full-screen note: title, date, typed text and handwriting pages.
/// S Pen: write; hold the side button (or use the eraser end / Eraser tool) to erase.
/// After the pen is used, fingers and palms don't draw (unless "Draw with finger" is on).
class NoteEditorScreen extends StatefulWidget {
  final Note note;
  const NoteEditorScreen({super.key, required this.note});

  @override
  State<NoteEditorScreen> createState() => _NoteEditorScreenState();
}

class _NoteEditorScreenState extends State<NoteEditorScreen> with WidgetsBindingObserver {
  final notes = NotesState.instance;
  late final title = TextEditingController(text: widget.note.title);
  late final text = TextEditingController(text: widget.note.text);
  late String date = widget.note.date;

  List<List<InkStroke>> pages = [[]];
  int page = 0;
  bool inkLoaded = false;
  int version = 0;

  InkTool tool = InkTool.pen;
  String color = 'ink';
  int size = 1; // 0 fine, 1 medium, 2 bold
  bool stylusSeen = false; // a pen was used in this note
  bool penOnly = false; // fingers/palms don't draw; turned on automatically when the pen is first used

  final undo = <(int, List<InkStroke>)>[];
  final redo = <(int, List<InkStroke>)>[];
  Timer? _autosave;
  bool _dirty = false;

  static const _penWidths = [0.0035, 0.006, 0.010];
  static const _eraserRadius = [0.015, 0.03, 0.055];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    title.addListener(_touch);
    text.addListener(_touch);
    notes.ink(widget.note.id).then((p) {
      if (!mounted) return;
      setState(() {
        pages = [
          for (final pg in p) [...pg],
        ];
        if (pages.isEmpty) pages = [[]];
        inkLoaded = true;
      });
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _autosave?.cancel();
    title.dispose();
    text.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState s) {
    if (s == AppLifecycleState.paused || s == AppLifecycleState.inactive) _save();
  }

  void _touch() {
    _dirty = true;
    _autosave?.cancel();
    _autosave = Timer(const Duration(seconds: 2), _save);
  }

  Future<void> _save() async {
    if (!_dirty || !inkLoaded) return;
    _dirty = false;
    final n = widget.note
      ..title = title.text.trim()
      ..text = text.text.trim()
      ..date = date;
    // Drop empty trailing pages.
    final keep = [...pages];
    while (keep.length > 1 && keep.last.isEmpty) {
      keep.removeLast();
    }
    await notes.save(n, ink: keep);
  }

  // ---------------- editing ----------------

  void _commit(List<InkStroke> before, List<InkStroke> after) {
    undo.add((page, before));
    if (undo.length > 100) undo.removeAt(0);
    redo.clear();
    setState(() {
      pages[page] = after;
      version++;
    });
    _touch();
  }

  void _undo() {
    if (undo.isEmpty) return;
    final (p, list) = undo.removeLast();
    redo.add((p, pages[p]));
    setState(() {
      page = p;
      pages[p] = list;
      version++;
    });
    _touch();
  }

  void _redo() {
    if (redo.isEmpty) return;
    final (p, list) = redo.removeLast();
    undo.add((p, pages[p]));
    setState(() {
      page = p;
      pages[p] = list;
      version++;
    });
    _touch();
  }

  Future<void> _pickDate() async {
    final d = await showDatePicker(context: context, initialDate: DateTime.parse(date), firstDate: DateTime(2020), lastDate: DateTime(2100));
    if (d != null) {
      setState(() => date = isoDate(d));
      _touch();
    }
  }

  Future<void> _delete() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('Delete this note?', style: TextStyle(fontSize: 18)),
        content: const Text('The text and handwriting are removed from this phone.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Cancel')),
          TextButton(
            onPressed: () => Navigator.pop(c, true),
            child: const Text('Delete', style: TextStyle(color: AppColors.red)),
          ),
        ],
      ),
    );
    if (ok != true) return;
    _autosave?.cancel();
    _dirty = false;
    await notes.delete(widget.note.id);
    if (mounted) Navigator.of(context).pop();
  }

  void _addPage() {
    setState(() {
      pages.add([]);
      page = pages.length - 1;
    });
    _touch();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final grey = theme.colorScheme.onSurfaceVariant;
    final d = DateTime.parse(date);
    final rel = fmtDay(d);
    return PopScope(
      onPopInvokedWithResult: (_, _) => _save(),
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Note'),
          actions: [
            IconButton(tooltip: 'Undo', onPressed: undo.isEmpty ? null : _undo, icon: const Icon(Icons.undo_rounded)),
            IconButton(tooltip: 'Redo', onPressed: redo.isEmpty ? null : _redo, icon: const Icon(Icons.redo_rounded)),
            IconButton(tooltip: 'Delete note', onPressed: _delete, icon: const Icon(Icons.delete_outline_rounded)),
          ],
        ),
        body: SafeArea(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 12, 0),
                child: Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: title,
                        textCapitalization: TextCapitalization.sentences,
                        style: const TextStyle(fontSize: 19, fontWeight: FontWeight.w700),
                        decoration: const InputDecoration(hintText: 'Title', border: InputBorder.none, isDense: true),
                      ),
                    ),
                    ActionChip(
                      avatar: const Icon(Icons.event_rounded, size: 17),
                      label: Text(rel == 'Today' || rel == 'Yesterday' || rel == 'Tomorrow' ? rel : DateFormat('EEE d MMM').format(d)),
                      onPressed: _pickDate,
                    ),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: TextField(
                  controller: text,
                  minLines: 1,
                  maxLines: 5,
                  textCapitalization: TextCapitalization.sentences,
                  style: const TextStyle(fontSize: 15, height: 1.4),
                  decoration: const InputDecoration(hintText: 'Type a note…', border: InputBorder.none, isDense: true),
                ),
              ),
              _toolbar(theme, grey),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(10, 0, 10, 4),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(14),
                    child: Container(
                      decoration: BoxDecoration(
                        color: theme.brightness == Brightness.light ? const Color(0xFFFFFDF7) : const Color(0xFF1A2228),
                        border: Border.all(color: theme.colorScheme.outlineVariant),
                        borderRadius: BorderRadius.circular(14),
                      ),
                      child: !inkLoaded
                          ? const Center(child: CircularProgressIndicator())
                          : InkCanvas(
                              key: ValueKey(page),
                              strokes: pages[page],
                              version: version,
                              tool: tool,
                              color: color,
                              penWidth: _penWidths[size],
                              eraserRadius: _eraserRadius[size],
                              fingerDraws: !penOnly,
                              onStylus: () {
                                if (!stylusSeen) {
                                  setState(() {
                                    stylusSeen = true;
                                    penOnly = true;
                                  });
                                }
                              },
                              onChange: _commit,
                            ),
                    ),
                  ),
                ),
              ),
              _pager(grey),
            ],
          ),
        ),
      ),
    );
  }

  Widget _toolbar(ThemeData theme, Color grey) {
    Widget toolBtn(InkTool t, Widget Function(Color) icon, String tip) => IconButton(
      tooltip: tip,
      isSelected: tool == t,
      style: IconButton.styleFrom(
        backgroundColor: tool == t ? AppColors.accent.withValues(alpha: 0.16) : null,
        foregroundColor: tool == t ? AppColors.accent : grey,
      ),
      onPressed: () => setState(() => tool = t),
      icon: icon(tool == t ? AppColors.accent : grey),
    );
    Widget swatch(String token) {
      final selected = color == token && tool != InkTool.eraser;
      return Semantics(
        button: true,
        selected: selected,
        label: '$token colour',
        child: GestureDetector(
          onTap: () => setState(() {
            color = token;
            tool = token == 'marker' ? InkTool.marker : InkTool.pen;
          }),
          child: Container(
            width: 26,
            height: 26,
            margin: const EdgeInsets.symmetric(horizontal: 3),
            decoration: BoxDecoration(
              color: token == 'marker' ? const Color(0xFFFFE066) : inkColor(token, theme.brightness),
              shape: BoxShape.circle,
              border: Border.all(color: selected ? AppColors.accent : theme.colorScheme.outlineVariant, width: selected ? 3 : 1),
            ),
          ),
        ),
      );
    }

    return SizedBox(
      height: 48,
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 8),
        children: [
          toolBtn(InkTool.pen, (c) => Icon(Icons.edit_rounded, size: 21, color: c), 'Pen'),
          toolBtn(InkTool.eraser, (c) => CustomPaint(size: const Size(22, 22), painter: _EraserIcon(c)), 'Eraser'),
          const SizedBox(width: 6),
          for (final t in ['ink', 'blue', 'red', 'green', 'marker']) Center(child: swatch(t)),
          const SizedBox(width: 6),
          IconButton(
            tooltip: 'Size: ${['fine', 'medium', 'bold'][size]}',
            onPressed: () => setState(() => size = (size + 1) % 3),
            icon: Container(
              width: 22,
              height: 22,
              alignment: Alignment.center,
              child: Container(
                width: [6.0, 11.0, 17.0][size],
                height: [6.0, 11.0, 17.0][size],
                decoration: BoxDecoration(color: grey, shape: BoxShape.circle),
              ),
            ),
          ),
          if (!stylusSeen)
            const SizedBox.shrink()
          else
            IconButton(
              tooltip: penOnly ? 'Only the pen draws (tap to let fingers draw)' : 'Fingers draw too (tap for pen only)',
              style: IconButton.styleFrom(foregroundColor: penOnly ? grey : AppColors.accent),
              onPressed: () => setState(() => penOnly = !penOnly),
              icon: Icon(penOnly ? Icons.do_not_touch_outlined : Icons.touch_app_rounded, size: 21),
            ),
        ],
      ),
    );
  }

  Widget _pager(Color grey) => SizedBox(
    height: 44,
    child: Row(
      children: [
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            stylusSeen ? 'S Pen: hold the side button to erase' : 'Write with your S Pen or finger',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(fontSize: 12, color: grey),
          ),
        ),
        IconButton(tooltip: 'Previous page', onPressed: page == 0 ? null : () => setState(() => page--), icon: const Icon(Icons.chevron_left_rounded)),
        Text('${page + 1} / ${pages.length}', style: TextStyle(fontSize: 13, color: grey)),
        IconButton(
          tooltip: page == pages.length - 1 ? 'Add page' : 'Next page',
          onPressed: page == pages.length - 1 ? _addPage : () => setState(() => page++),
          icon: Icon(page == pages.length - 1 ? Icons.note_add_outlined : Icons.chevron_right_rounded),
        ),
        const SizedBox(width: 4),
      ],
    ),
  );
}

/// The handwriting surface. Claims every pointer on it, so nothing else scrolls while writing.
class InkCanvas extends StatefulWidget {
  final List<InkStroke> strokes;
  final int version;
  final InkTool tool;
  final String color;
  final double penWidth;
  final double eraserRadius;
  final bool fingerDraws;
  final VoidCallback onStylus;
  final void Function(List<InkStroke> before, List<InkStroke> after) onChange;

  const InkCanvas({
    super.key,
    required this.strokes,
    required this.version,
    required this.tool,
    required this.color,
    required this.penWidth,
    required this.eraserRadius,
    required this.fingerDraws,
    required this.onStylus,
    required this.onChange,
  });

  @override
  State<InkCanvas> createState() => _InkCanvasState();
}

class _InkCanvasState extends State<InkCanvas> {
  int? _pointer;
  bool _erasing = false;
  InkStroke? _live;
  List<InkStroke>? _before; // strokes when the gesture started (for undo)
  List<InkStroke>? _working; // strokes while erasing
  Offset? _eraserAt;
  int _tick = 0;

  bool _isStylus(PointerEvent e) => e.kind == PointerDeviceKind.stylus || e.kind == PointerDeviceKind.invertedStylus;

  bool _wantsErase(PointerEvent e) =>
      widget.tool == InkTool.eraser ||
      e.kind == PointerDeviceKind.invertedStylus ||
      (e.kind == PointerDeviceKind.stylus && (e.buttons & (kPrimaryStylusButton | kSecondaryStylusButton)) != 0);

  double _pressure(PointerEvent e) {
    final range = e.pressureMax - e.pressureMin;
    if (range <= 0) return 0.5;
    return ((e.pressure - e.pressureMin) / range).clamp(0.0, 1.0);
  }

  void _down(PointerDownEvent e, double w) {
    if (_pointer != null) return;
    if (_isStylus(e)) {
      widget.onStylus();
    } else if (!widget.fingerDraws) {
      return; // palm or finger while the pen is in use
    }
    _pointer = e.pointer;
    _before = widget.strokes;
    final at = e.localPosition / w;
    if (_wantsErase(e)) {
      _erasing = true;
      _working = widget.strokes;
      _eraseAt(at);
    } else {
      final marker = widget.tool == InkTool.marker || widget.color == 'marker';
      _live = InkStroke(
        color: marker ? 'marker' : widget.color,
        width: marker ? widget.penWidth * 5 : widget.penWidth,
        points: [at],
        pressure: _isStylus(e) && !marker ? [_pressure(e)] : null,
      );
    }
    setState(() {});
  }

  void _move(PointerMoveEvent e, double w) {
    if (e.pointer != _pointer) return;
    final at = e.localPosition / w;
    // The S Pen button can be pressed mid-stroke: switch to erasing.
    if (!_erasing && _wantsErase(e)) {
      if (_live != null && _live!.points.length > 1) _working = [...widget.strokes, _live!];
      _working ??= widget.strokes;
      _live = null;
      _erasing = true;
    }
    if (_erasing) {
      _eraseAt(at);
    } else if (_live != null) {
      final last = _live!.points.last;
      if ((at - last).distance < 0.0012) return;
      _live!.points.add(at);
      if (_live!.pressure.isNotEmpty) _live!.pressure.add(_pressure(e));
    }
    setState(() => _tick++);
  }

  void _eraseAt(Offset at) {
    _eraserAt = at;
    final next = eraseAt(_working!, at, widget.eraserRadius);
    if (next != null) _working = next;
  }

  void _up(PointerEvent e) {
    if (e.pointer != _pointer) return;
    final before = _before ?? widget.strokes;
    if (_erasing) {
      if (_working != null && !identical(_working, before)) widget.onChange(before, _working!);
    } else if (_live != null) {
      widget.onChange(before, [...before, _live!]);
    }
    _pointer = null;
    _erasing = false;
    _live = null;
    _working = null;
    _before = null;
    _eraserAt = null;
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return LayoutBuilder(
      builder: (context, box) {
        final w = box.maxWidth;
        return RawGestureDetector(
          // Win every gesture on the page so writing never scrolls or swipes something else.
          gestures: {_ClaimAll: GestureRecognizerFactoryWithHandlers<_ClaimAll>(() => _ClaimAll(), (_) {})},
          child: Listener(
            behavior: HitTestBehavior.opaque,
            onPointerDown: (e) => _down(e, w),
            onPointerMove: (e) => _move(e, w),
            onPointerUp: _up,
            onPointerCancel: _up,
            child: CustomPaint(
              size: Size(w, box.maxHeight),
              painter: InkPainter(
                strokes: _erasing ? (_working ?? widget.strokes) : widget.strokes,
                live: _live,
                brightness: theme.brightness,
                lines: true,
                lineColor: theme.brightness == Brightness.light ? const Color(0x1A1565C0) : const Color(0x22FFFFFF),
                version: widget.version * 100000 + _tick,
              ),
              foregroundPainter: _erasing && _eraserAt != null ? _EraserRing(_eraserAt! * w, widget.eraserRadius * w, theme.colorScheme.outline) : null,
            ),
          ),
        );
      },
    );
  }
}

class _EraserRing extends CustomPainter {
  final Offset at;
  final double r;
  final Color color;
  _EraserRing(this.at, this.r, this.color);

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawCircle(at, r, Paint()..color = color.withValues(alpha: 0.12));
    canvas.drawCircle(
      at,
      r,
      Paint()
        ..color = color
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.2,
    );
  }

  @override
  bool shouldRepaint(_EraserRing old) => old.at != at || old.r != r;
}

/// Accepts every pointer immediately, so parent gestures (scrolling, swipes) never start on the page.
class _ClaimAll extends OneSequenceGestureRecognizer {
  @override
  void addAllowedPointer(PointerDownEvent event) {
    startTrackingPointer(event.pointer, event.transform);
    resolvePointer(event.pointer, GestureDisposition.accepted);
  }

  @override
  void handleEvent(PointerEvent event) {
    if (event is PointerUpEvent || event is PointerCancelEvent) stopTrackingPointer(event.pointer);
  }

  @override
  void didStopTrackingLastPointer(int pointer) {}

  @override
  String get debugDescription => 'claim all';
}

/// A small eraser drawing (Material Icons has none): a tilted block with a lighter tip.
class _EraserIcon extends CustomPainter {
  final Color color;
  _EraserIcon(this.color);

  @override
  void paint(Canvas canvas, Size size) {
    final u = size.width / 24;
    canvas.save();
    canvas.translate(12 * u, 11 * u);
    canvas.rotate(-0.7);
    final body = RRect.fromRectAndRadius(Rect.fromCenter(center: Offset.zero, width: 18 * u, height: 9 * u), Radius.circular(2 * u));
    canvas.drawRRect(body, Paint()..color = color);
    canvas.drawRRect(
      RRect.fromRectAndRadius(Rect.fromLTWH(-9 * u, -4.5 * u, 7 * u, 9 * u), Radius.circular(2 * u)),
      Paint()..color = Color.lerp(color, Colors.white, 0.55)!,
    );
    canvas.restore();
    canvas.drawLine(
      Offset(4 * u, 21 * u),
      Offset(20 * u, 21 * u),
      Paint()
        ..color = color
        ..strokeWidth = 1.6 * u
        ..strokeCap = StrokeCap.round,
    );
  }

  @override
  bool shouldRepaint(_EraserIcon old) => old.color != color;
}

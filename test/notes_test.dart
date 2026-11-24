import 'dart:convert';

import 'package:flutter/gestures.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:remindly/sprint/ink.dart';
import 'package:remindly/sprint/note_editor.dart';
import 'package:remindly/sprint/notes_state.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  InkStroke line(double y, {String color = 'ink'}) =>
      InkStroke(color: color, width: 0.006, points: [for (var x = 0.1; x <= 0.9; x += 0.05) Offset(x, y)]);

  group('eraser', () {
    test('cuts a stroke where it passes and keeps both ends', () {
      final out = eraseAt([line(0.2)], const Offset(0.5, 0.2), 0.03)!;
      expect(out.length, 2);
      expect(out[0].points.last.dx, lessThan(0.5));
      expect(out[1].points.first.dx, greaterThan(0.5));
    });

    test('leaves strokes it does not touch, and returns null when nothing changed', () {
      final a = line(0.2), b = line(0.6);
      final out = eraseAt([a, b], const Offset(0.5, 0.6), 0.02)!;
      expect(out.first, same(a));
      expect(eraseAt([a], const Offset(0.5, 0.9), 0.02), isNull);
    });

    test('erasing the end of a stroke removes it entirely', () {
      final short = InkStroke(color: 'ink', width: 0.006, points: const [Offset(0.5, 0.5), Offset(0.51, 0.5)]);
      expect(eraseAt([short], const Offset(0.505, 0.5), 0.03), isEmpty);
    });
  });

  test('stroke json round trip keeps points, colour and pressure', () {
    final s = InkStroke(color: 'blue', width: 0.0061234, points: const [Offset(0.1, 0.2), Offset(0.3, 0.4)], pressure: [0.25, 0.8]);
    final back = InkStroke.fromJson(jsonDecode(jsonEncode(s.toJson())) as Map<String, dynamic>);
    expect(back.color, 'blue');
    expect(back.width, closeTo(0.0061, 0.0001));
    expect(back.points, const [Offset(0.1, 0.2), Offset(0.3, 0.4)]);
    expect(back.pressure, [0.25, 0.8]);
  });

  group('notes storage', () {
    const ch = MethodChannel('remindly/notes-test');
    final files = <String, String>{};
    setUp(() {
      files.clear();
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(ch, (call) async {
        switch (call.method) {
          case 'notesGet':
            return files['index'] ?? '[]';
          case 'notesSave':
            files['index'] = call.arguments as String;
          case 'inkGet':
            return files['ink${call.arguments}'];
          case 'inkSave':
            final a = call.arguments as Map;
            files['ink${a['id']}'] = a['json'] as String;
          case 'inkDelete':
            files.remove('ink${call.arguments}');
        }
        return null;
      });
    });

    test('saves text and handwriting, reloads them, and deletes', () async {
      final s = NotesState(channel: ch);
      final n = s.create(date: '2026-11-24')..title = 'Sprint planning';
      await s.save(n, ink: [[line(0.3)], []]);
      expect(n.hasInk, isTrue);
      final again = NotesState(channel: ch);
      await again.load();
      expect(again.notes.single.title, 'Sprint planning');
      final pages = await again.ink(n.id);
      expect(pages.first.single.points.length, line(0.3).points.length);
      await again.delete(n.id);
      expect(files.containsKey('ink${n.id}'), isFalse);
      expect(jsonDecode(files['index']!), isEmpty);
    });

    test('an empty new note is not kept', () async {
      final s = NotesState(channel: ch);
      final n = s.create();
      await s.save(n, ink: [[]]);
      expect(s.notes, isEmpty);
    });
  });

  group('canvas with S Pen', () {
    Future<List<List<InkStroke>>> run(WidgetTester t, Future<void> Function(Offset origin, Size size) gesture, {InkTool tool = InkTool.pen}) async {
      var strokes = <InkStroke>[];
      var fingerDraws = true;
      await t.pumpWidget(MaterialApp(
        home: StatefulBuilder(
          builder: (context, set) => Scaffold(
            body: SizedBox(
              width: 400,
              height: 600,
              child: InkCanvas(
                strokes: strokes,
                version: strokes.length,
                tool: tool,
                color: 'ink',
                penWidth: 0.006,
                eraserRadius: 0.03,
                fingerDraws: fingerDraws,
                onStylus: () => set(() => fingerDraws = false),
                onChange: (_, after) => set(() => strokes = after),
              ),
            ),
          ),
        ),
      ));
      final box = t.getRect(find.byType(InkCanvas));
      await gesture(box.topLeft, box.size);
      await t.pump();
      return [strokes];
    }

    Future<void> drag(WidgetTester t, Offset from, Offset to, {PointerDeviceKind kind = PointerDeviceKind.stylus, int buttons = kPrimaryButton, int pointer = 1}) async {
      final g = await t.startGesture(from, kind: kind, pointer: pointer, buttons: buttons);
      for (var i = 1; i <= 10; i++) {
        await g.moveTo(Offset.lerp(from, to, i / 10)!);
      }
      await g.up();
    }

    testWidgets('pen writes a stroke with pressure', (t) async {
      final r = await run(t, (o, s) => drag(t, o + const Offset(40, 100), o + const Offset(360, 100)));
      expect(r.first.length, 1);
      expect(r.first.single.points.length, greaterThan(5));
      expect(r.first.single.pressure.length, r.first.single.points.length);
    });

    testWidgets('after the pen is used, a finger or palm does not draw', (t) async {
      final r = await run(t, (o, s) async {
        await drag(t, o + const Offset(40, 100), o + const Offset(360, 100));
        await t.pump();
        await drag(t, o + const Offset(40, 300), o + const Offset(360, 300), kind: PointerDeviceKind.touch, pointer: 2);
      });
      expect(r.first.length, 1);
    });

    testWidgets('holding the S Pen side button erases', (t) async {
      final r = await run(t, (o, s) async {
        await drag(t, o + const Offset(40, 100), o + const Offset(360, 100));
        await t.pump();
        // Cross the line with the side button held.
        await drag(t, o + const Offset(200, 40), o + const Offset(200, 160), buttons: kPrimaryButton | kPrimaryStylusButton, pointer: 2);
      });
      expect(r.first.length, 2, reason: 'the line is cut in two where the eraser crossed it');
    });

    testWidgets('eraser tool erases with a finger before any pen is used', (t) async {
      final r = await run(
        t,
        (o, s) => drag(t, o + const Offset(200, 40), o + const Offset(200, 160), kind: PointerDeviceKind.touch),
        tool: InkTool.eraser,
      );
      expect(r.first, isEmpty);
    });
  });
}

import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';

import '../models.dart' show isoDate;
import 'ink.dart';

/// A dated note: a title, typed text and handwritten pages.
class Note {
  final int id;
  String date; // yyyy-MM-dd
  String title;
  String text;
  int pages; // handwriting pages (at least 1)
  bool hasInk;
  int updatedAt;

  Note({required this.id, required this.date, this.title = '', this.text = '', this.pages = 1, this.hasInk = false, int? updatedAt})
    : updatedAt = updatedAt ?? DateTime.now().millisecondsSinceEpoch;

  bool get isEmpty => title.trim().isEmpty && text.trim().isEmpty && !hasInk;

  Map<String, dynamic> toJson() => {'id': id, 'date': date, 'title': title, 'text': text, 'pages': pages, 'hasInk': hasInk, 'updatedAt': updatedAt};

  factory Note.fromJson(Map<String, dynamic> j) => Note(
    id: (j['id'] as num).toInt(),
    date: j['date'] as String? ?? isoDate(DateTime.now()),
    title: j['title'] as String? ?? '',
    text: j['text'] as String? ?? '',
    pages: (j['pages'] as num?)?.toInt() ?? 1,
    hasInk: j['hasInk'] as bool? ?? false,
    updatedAt: (j['updatedAt'] as num?)?.toInt(),
  );
}

/// Notes for Daily Sprint. Stored on the phone in their own files (an index, plus one file of
/// handwriting per note), so big handwriting never slows the rest of the app. Included in backups.
class NotesState extends ChangeNotifier {
  NotesState({MethodChannel? channel}) : _ch = channel ?? const MethodChannel('remindly/native');
  static final NotesState instance = NotesState();

  final MethodChannel _ch;
  List<Note> notes = [];
  final Map<int, List<List<InkStroke>>> _ink = {};
  bool loaded = false;

  /// Newest date first, then most recently changed.
  List<Note> get sorted => [...notes]
    ..sort((a, b) {
      final d = b.date.compareTo(a.date);
      return d != 0 ? d : b.updatedAt.compareTo(a.updatedAt);
    });

  Note? byId(int id) {
    for (final n in notes) {
      if (n.id == id) return n;
    }
    return null;
  }

  Future<void> load() async {
    try {
      final raw = await _ch.invokeMethod<String>('notesGet');
      final list = (jsonDecode(raw ?? '[]') as List).map((e) => Note.fromJson(Map<String, dynamic>.from(e as Map))).toList();
      notes = list;
    } catch (_) {}
    loaded = true;
    notifyListeners();
  }

  Future<void> _saveIndex() async {
    notifyListeners();
    try {
      await _ch.invokeMethod('notesSave', jsonEncode(notes.map((n) => n.toJson()).toList()));
    } catch (_) {}
  }

  Note create({String? date}) {
    final id = notes.fold<int>(0, (m, n) => n.id > m ? n.id : m) + 1;
    final n = Note(id: id, date: date ?? isoDate(DateTime.now()));
    notes.add(n);
    _ink[id] = [[]];
    return n;
  }

  /// Saves a note (and its handwriting when given). Empty new notes are not kept.
  Future<void> save(Note n, {List<List<InkStroke>>? ink}) async {
    if (ink != null) {
      _ink[n.id] = ink;
      n.pages = ink.length.clamp(1, 99);
      n.hasInk = ink.any((p) => p.isNotEmpty);
    }
    if (n.isEmpty) {
      await delete(n.id);
      return;
    }
    n.updatedAt = DateTime.now().millisecondsSinceEpoch;
    if (byId(n.id) == null) notes.add(n);
    if (ink != null) {
      try {
        await _ch.invokeMethod('inkSave', {
          'id': n.id,
          'json': jsonEncode([
            for (final page in ink) [for (final s in page) s.toJson()],
          ]),
        });
      } catch (_) {}
    }
    await _saveIndex();
  }

  Future<void> delete(int id) async {
    notes.removeWhere((n) => n.id == id);
    _ink.remove(id);
    try {
      await _ch.invokeMethod('inkDelete', id);
    } catch (_) {}
    await _saveIndex();
  }

  /// Handwriting pages of a note (cached after the first read).
  Future<List<List<InkStroke>>> ink(int id) async {
    final cached = _ink[id];
    if (cached != null) return cached;
    var pages = <List<InkStroke>>[[]];
    try {
      final raw = await _ch.invokeMethod<String>('inkGet', id);
      if (raw != null && raw.isNotEmpty) {
        pages = [
          for (final p in jsonDecode(raw) as List) [for (final s in p as List) InkStroke.fromJson(Map<String, dynamic>.from(s as Map))],
        ];
        if (pages.isEmpty) pages = [[]];
      }
    } catch (_) {}
    _ink[id] = pages;
    return pages;
  }

  /// Already-loaded handwriting (for thumbnails), or null.
  List<List<InkStroke>>? cachedInk(int id) => _ink[id];
}

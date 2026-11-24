import 'package:intl/intl.dart';
import 'package:material_ui/material_ui.dart';

import '../format.dart' show fmtDay;
import '../main.dart' show AppColors;
import 'ink.dart';
import 'insights_view.dart' show SprintColors;
import 'note_editor.dart';
import 'notes_state.dart';

/// Daily Sprint › Notes: dated notes with typed text and S Pen handwriting.
class NotesView extends StatefulWidget {
  const NotesView({super.key});

  @override
  State<NotesView> createState() => _NotesViewState();
}

class _NotesViewState extends State<NotesView> with AutomaticKeepAliveClientMixin {
  final notes = NotesState.instance;

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    if (!notes.loaded) notes.load();
  }

  Future<void> _open(Note n) => Navigator.of(context).push(MaterialPageRoute(builder: (_) => NoteEditorScreen(note: n)));

  String _dayLabel(String iso) {
    final d = DateTime.parse(iso);
    final rel = fmtDay(d);
    if (rel == 'Today' || rel == 'Yesterday' || rel == 'Tomorrow') return '$rel · ${DateFormat('d MMM').format(d)}';
    return DateFormat(d.year == DateTime.now().year ? 'EEEE, d MMM' : 'EEEE, d MMM y').format(d);
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final c = SprintColors.of(context);
    return ListenableBuilder(
      listenable: notes,
      builder: (context, _) {
        final list = notes.sorted.where((n) => !n.isEmpty).toList();
        return Scaffold(
          floatingActionButton: list.isEmpty
              ? null
              : FloatingActionButton.extended(
                  heroTag: 'newNote',
                  onPressed: () => _open(notes.create()),
                  icon: const Icon(Icons.edit_note_rounded),
                  label: const Text('New note'),
                ),
          body: list.isEmpty
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(32),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Container(
                          width: 84,
                          height: 84,
                          decoration: BoxDecoration(color: AppColors.accent.withValues(alpha: 0.14), shape: BoxShape.circle),
                          child: const Icon(Icons.draw_outlined, size: 40, color: AppColors.accent),
                        ),
                        const SizedBox(height: 16),
                        Text(
                          'Your notes',
                          style: TextStyle(fontSize: 19, fontWeight: FontWeight.w700, color: c.ink),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          'Type, or write and sketch with your S Pen.\nHold the pen\'s side button to erase.',
                          textAlign: TextAlign.center,
                          style: TextStyle(fontSize: 14, color: c.muted, height: 1.45),
                        ),
                        const SizedBox(height: 18),
                        FilledButton.icon(onPressed: () => _open(notes.create()), icon: const Icon(Icons.edit_note_rounded), label: const Text('New note')),
                      ],
                    ),
                  ),
                )
              : ListView(
                  padding: const EdgeInsets.fromLTRB(12, 8, 12, 96),
                  children: [
                    for (var i = 0; i < list.length; i++) ...[
                      if (i == 0 || list[i].date != list[i - 1].date)
                        Padding(
                          padding: EdgeInsets.fromLTRB(4, i == 0 ? 4 : 14, 4, 6),
                          child: Text(
                            _dayLabel(list[i].date),
                            style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: c.muted),
                          ),
                        ),
                      _NoteCard(note: list[i], onTap: () => _open(list[i])),
                      const SizedBox(height: 8),
                    ],
                  ],
                ),
        );
      },
    );
  }
}

class _NoteCard extends StatelessWidget {
  final Note note;
  final VoidCallback onTap;
  const _NoteCard({required this.note, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final c = SprintColors.of(context);
    final firstLine = note.text.split('\n').first.trim();
    final heading = note.title.isNotEmpty ? note.title : (firstLine.isNotEmpty ? firstLine : 'Handwritten note');
    final body = note.title.isNotEmpty ? note.text : note.text.split('\n').skip(1).join(' ').trim();
    return Material(
      color: c.card,
      borderRadius: BorderRadius.circular(14),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(14, 12, 12, 12),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      heading,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: c.ink),
                    ),
                    if (body.isNotEmpty) ...[
                      const SizedBox(height: 3),
                      Text(
                        body,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(fontSize: 13, color: c.muted, height: 1.35),
                      ),
                    ],
                    const SizedBox(height: 6),
                    Row(
                      children: [
                        if (note.hasInk) ...[
                          Icon(Icons.draw_outlined, size: 14, color: c.muted),
                          const SizedBox(width: 4),
                          Text(note.pages > 1 ? '${note.pages} pages' : 'Handwriting', style: TextStyle(fontSize: 12, color: c.muted)),
                          const SizedBox(width: 10),
                        ],
                        Text(
                          'Edited ${DateFormat('d MMM, h:mm a').format(DateTime.fromMillisecondsSinceEpoch(note.updatedAt))}',
                          style: TextStyle(fontSize: 12, color: c.muted),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              if (note.hasInk) ...[const SizedBox(width: 10), _Thumb(id: note.id)],
            ],
          ),
        ),
      ),
    );
  }
}

/// First handwriting page, small.
class _Thumb extends StatelessWidget {
  final int id;
  const _Thumb({required this.id});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final notes = NotesState.instance;
    return Container(
      width: 76,
      height: 76,
      decoration: BoxDecoration(
        color: theme.brightness == Brightness.light ? const Color(0xFFFFFDF7) : const Color(0xFF1A2228),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: theme.colorScheme.outlineVariant),
      ),
      clipBehavior: Clip.antiAlias,
      child: FutureBuilder<List<List<InkStroke>>>(
        future: notes.cachedInk(id) != null ? Future.value(notes.cachedInk(id)) : notes.ink(id),
        builder: (context, snap) {
          final pages = snap.data;
          if (pages == null || pages.isEmpty) return const SizedBox.shrink();
          return CustomPaint(
            painter: InkPainter(strokes: pages.first, brightness: theme.brightness),
          );
        },
      ),
    );
  }
}

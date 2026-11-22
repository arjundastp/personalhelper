import 'package:material_ui/material_ui.dart';

import '../models.dart';
import '../native.dart';

/// Lists the app's own tunes plus every alarm, ringtone and notification sound on the phone.
/// Tapping a row plays a preview; "Use this sound" returns the choice.
class SoundPickerScreen extends StatefulWidget {
  final String? selectedUri;
  final String title;
  const SoundPickerScreen({super.key, this.selectedUri, this.title = 'Choose a sound'});

  @override
  State<SoundPickerScreen> createState() => _SoundPickerScreenState();
}

class _SoundPickerScreenState extends State<SoundPickerScreen> {
  Map<String, List<SoundOption>> sounds = {};
  SoundOption? selected;
  String? playing;
  bool loading = true;

  static const tabs = [
    ('app', 'REMINDLY', Icons.auto_awesome_rounded),
    ('alarm', 'ALARM', Icons.alarm_rounded),
    ('ringtone', 'RINGTONE', Icons.ring_volume_rounded),
    ('notification', 'OTHER', Icons.notifications_rounded),
  ];

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    Native.stopPreview();
    super.dispose();
  }

  Future<void> _load() async {
    final s = await Native.sounds();
    SoundOption? sel;
    for (final list in s.values) {
      for (final o in list) {
        if (o.uri == widget.selectedUri) sel = o;
      }
    }
    if (!mounted) return;
    setState(() {
      sounds = s;
      selected = sel;
      loading = false;
    });
  }

  Future<void> _tap(SoundOption o) async {
    setState(() => selected = o);
    if (playing == o.uri) {
      await Native.stopPreview();
      setState(() => playing = null);
      return;
    }
    final ok = await Native.previewSound(o.uri);
    if (mounted) setState(() => playing = ok ? o.uri : null);
  }

  Future<void> _pickFile() async {
    await Native.stopPreview();
    final f = await Native.pickAudioFile();
    if (f == null || !mounted) return;
    setState(() {
      selected = f;
      playing = null;
      sounds = {...sounds, 'file': [f]};
    });
    _tap(f);
  }

  int get _initialTab {
    final g = selected?.group;
    final i = tabs.indexWhere((t) => t.$1 == g);
    return i < 0 ? 0 : i;
  }

  @override
  Widget build(BuildContext context) {
    
    if (loading) {
      return Scaffold(appBar: AppBar(title: Text(widget.title)), body: const Center(child: CircularProgressIndicator()));
    }
    return DefaultTabController(
      length: tabs.length,
      initialIndex: _initialTab,
      child: Scaffold(
        appBar: AppBar(
          title: Text(widget.title),
          bottom: TabBar(
            isScrollable: true,
            tabAlignment: TabAlignment.start,
            tabs: [for (final t in tabs) Tab(text: t.$2)],
          ),
        ),
        bottomNavigationBar: SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (selected != null)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: Text('Chosen: ${selected!.title}',
                        maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 16)),
                  ),
                Row(children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: _pickFile,
                      icon: const Icon(Icons.folder_open_rounded),
                      label: const Text('My music'),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: FilledButton(
                      onPressed: selected == null ? null : () => Navigator.of(context).pop(selected),
                      child: const Text('OK'),
                    ),
                  ),
                ]),
              ],
            ),
          ),
        ),
        body: TabBarView(
          children: [
            for (final t in tabs) _list(context, [...?sounds[t.$1], if (t.$1 == 'app') ...?sounds['file']]),
          ],
        ),
      ),
    );
  }

  Widget _list(BuildContext context, List<SoundOption> items) {
    final theme = Theme.of(context);
    if (items.isEmpty) {
      return const Center(child: Padding(padding: EdgeInsets.all(32), child: Text('No sounds found on this phone.')));
    }
    return ListView.builder(
      padding: const EdgeInsets.symmetric(vertical: 8),
      itemCount: items.length,
      itemBuilder: (context, i) {
        final o = items[i];
        final isSel = selected?.uri == o.uri;
        final isPlaying = playing == o.uri;
        return ListTile(
          minVerticalPadding: 14,
          contentPadding: const EdgeInsets.symmetric(horizontal: 20),
          leading: Icon(isSel ? Icons.radio_button_checked_rounded : Icons.radio_button_off_rounded,
              color: isSel ? const Color(0xFF00A884) : theme.colorScheme.onSurfaceVariant, size: 28),
          title: Text(o.title, style: TextStyle(fontSize: 17, fontWeight: isSel ? FontWeight.w700 : FontWeight.w400)),
          subtitle: o.group == 'file' ? const Text('From your files') : null,
          trailing: IconButton(
            tooltip: isPlaying ? 'Stop' : 'Play',
            iconSize: 30,
            onPressed: () => _tap(o),
            icon: Icon(isPlaying ? Icons.stop_circle_rounded : Icons.play_circle_outline_rounded,
                color: const Color(0xFF00A884)),
          ),
          onTap: () => _tap(o),
        );
      },
    );
  }
}

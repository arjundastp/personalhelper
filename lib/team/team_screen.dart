import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:material_ui/material_ui.dart';

import '../main.dart' show AppColors;
import '../sprint/insights_view.dart' show SprintColors;
import '../widgets.dart';
import 'team_state.dart';

const _actionBg = Color(0xFFFFF4E5);

/// The "Team summary" tab: yesterday in Microsoft Teams, summarised on this phone.
class TeamScreen extends StatelessWidget {
  const TeamScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final t = TeamState.instance;
    return ListenableBuilder(
      listenable: t,
      builder: (context, _) => Scaffold(
        appBar: AppBar(
          title: const Text('Team summary'),
          actions: [
            IconButton(
              tooltip: 'Team summary settings',
              onPressed: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const TeamSettingsScreen())),
              icon: const Icon(Icons.tune_rounded),
            ),
          ],
        ),
        body: t.configured && t.signedIn ? const _SummaryView() : const _SetupView(),
      ),
    );
  }
}

// ------------------------------------------------------------------ setup

class _SetupView extends StatefulWidget {
  const _SetupView();

  @override
  State<_SetupView> createState() => _SetupViewState();
}

class _SetupViewState extends State<_SetupView> {
  final t = TeamState.instance;
  late final tenant = TextEditingController(text: t.tenantId);
  late final client = TextEditingController(text: t.clientId);
  late final scope = TextEditingController(text: t.scope.isEmpty ? TeamState.defaultScope : t.scope);
  late final server = TextEditingController(text: t.serverUrl.isEmpty ? TeamState.defaultServer : t.serverUrl);
  late String mode = t.mode;
  String? error;

  @override
  void dispose() {
    tenant.dispose();
    client.dispose();
    scope.dispose();
    server.dispose();
    super.dispose();
  }

  Future<void> _signIn() async {
    if (!TeamState.validId(tenant.text) || !TeamState.validId(client.text)) {
      setState(() => error = 'Both IDs look like 8-4-4-4-12 characters, e.g. 1a2b3c4d-…. Please check them.');
      return;
    }
    setState(() => error = null);
    await t.setIds(tenant.text, client.text, mode: mode, scope: scope.text, serverUrl: server.text);
    final e = await t.signIn();
    if (mounted && e != null) {
      setState(
        () => error = e.contains('AADSTS650052')
            ? 'Your company has not switched on the Microsoft service this permission belongs to (error AADSTS650052). '
                  'Use the Microsoft Graph connection, or ask IT to enable the Teams MCP server.\n\n$e'
            : e.contains('AADSTS65001') || e.contains('consent')
            ? 'Chat.Read has not been approved for DayMate yet. Ask IT to grant admin consent for it in Entra.\n\n$e'
            : 'Sign-in did not work: $e',
      );
    }
  }

  Widget _promise(SprintColors c, String title, String text) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 5),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 24,
          height: 24,
          decoration: BoxDecoration(color: c.done.withValues(alpha: 0.15), shape: BoxShape.circle),
          child: Icon(Icons.check_rounded, size: 15, color: c.ink),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Text.rich(
            TextSpan(
              children: [
                TextSpan(
                  text: '$title  ',
                  style: const TextStyle(fontWeight: FontWeight.w600),
                ),
                TextSpan(
                  text: text,
                  style: TextStyle(color: c.muted),
                ),
              ],
            ),
            style: const TextStyle(fontSize: 13.5, height: 1.35),
          ),
        ),
      ],
    ),
  );

  @override
  Widget build(BuildContext context) {
    final c = SprintColors.of(context);
    return ListView(
      padding: const EdgeInsets.fromLTRB(18, 16, 18, 24),
      children: [
        Text(
          'Connect your work Teams',
          style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600, color: c.ink),
        ),
        const SizedBox(height: 4),
        Text(
          'DayMate reads yesterday\'s Teams chats with your work account (read-only) and summarises them on this phone.',
          style: TextStyle(fontSize: 13.5, color: c.muted, height: 1.4),
        ),
        const SizedBox(height: 10),
        _promise(c, 'Read-only.', 'Uses Chat.Read, which can only read. The app never posts, edits or deletes.'),
        _promise(c, 'Stays on your phone.', 'The AI runs on the phone. Nothing goes to any other server or AI service.'),
        _promise(c, 'Kept 10 days.', 'Older summaries delete themselves. Raw messages are never saved.'),
        const SizedBox(height: 14),
        Text(
          'Your company\'s IDs',
          style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: c.ink),
        ),
        Text(
          'From the DayMate app registration in Microsoft Entra (Overview page). Saved only on this phone.',
          style: TextStyle(fontSize: 12.5, color: c.muted),
        ),
        TextField(
          controller: tenant,
          style: const TextStyle(fontSize: 14.5),
          decoration: const InputDecoration(labelText: 'Directory (tenant) ID', isDense: true),
        ),
        TextField(
          controller: client,
          style: const TextStyle(fontSize: 14.5),
          decoration: const InputDecoration(labelText: 'Application (client) ID', isDense: true),
        ),
        const SizedBox(height: 14),
        Text(
          'Connection',
          style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: c.ink),
        ),
        RadioRow(
          label: 'Microsoft Graph · Chat.Read (recommended)',
          selected: mode == 'graph',
          onTap: () => setState(() => mode = 'graph'),
        ),
        RadioRow(label: 'Company Teams MCP server', selected: mode == 'mcp', onTap: () => setState(() => mode = 'mcp')),
        if (mode == 'mcp')
          Theme(
            data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
            child: ExpansionTile(
              tilePadding: EdgeInsets.zero,
              childrenPadding: EdgeInsets.zero,
              title: Text('Advanced (only if IT gives you different values)', style: TextStyle(fontSize: 13.5, color: c.muted)),
              children: [
                TextField(
                  controller: scope,
                  style: const TextStyle(fontSize: 13),
                  decoration: const InputDecoration(labelText: 'Teams server permission (scope)', isDense: true),
                ),
                TextField(
                  controller: server,
                  style: const TextStyle(fontSize: 13),
                  decoration: const InputDecoration(labelText: 'Teams server address', isDense: true),
                ),
                Align(
                  alignment: Alignment.centerLeft,
                  child: TextButton(
                    onPressed: () => setState(() {
                      scope.text = TeamState.defaultScope;
                      server.text = TeamState.defaultServer;
                    }),
                    child: const Text('Reset to defaults'),
                  ),
                ),
              ],
            ),
          ),
        if (error != null)
          Padding(
            padding: const EdgeInsets.only(top: 10),
            child: SelectableText(error!, style: const TextStyle(fontSize: 13, color: AppColors.red)),
          ),
        const SizedBox(height: 18),
        SizedBox(
          width: double.infinity,
          child: OutlinedButton.icon(
            style: OutlinedButton.styleFrom(minimumSize: const Size(0, 46)),
            onPressed: TeamState.instance.busy ? null : _signIn,
            icon: TeamState.instance.busy
                ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                : const _MsLogo(),
            label: const Text('Sign in with work account'),
          ),
        ),
      ],
    );
  }
}

class _MsLogo extends StatelessWidget {
  const _MsLogo();

  @override
  Widget build(BuildContext context) {
    Widget sq(Color c) => Container(width: 8, height: 8, color: c);
    return SizedBox(
      width: 18,
      height: 18,
      child: Column(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [sq(const Color(0xFFF25022)), sq(const Color(0xFF7FBA00))]),
          Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [sq(const Color(0xFF00A4EF)), sq(const Color(0xFFFFB900))]),
        ],
      ),
    );
  }
}

// ------------------------------------------------------------------ summaries

class _SummaryView extends StatefulWidget {
  const _SummaryView();

  @override
  State<_SummaryView> createState() => _SummaryViewState();
}

class _SummaryViewState extends State<_SummaryView> {
  final t = TeamState.instance;
  int selected = 0;
  final open = <int>{0};

  Future<void> _pull() async {
    final e = await t.pullYesterday();
    if (!mounted) return;
    setState(() {
      selected = 0;
      open
        ..clear()
        ..add(0);
    });
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e == null ? 'Summary ready' : 'Did not work – see details below')));
  }

  String _dayLabel(String iso) {
    final d = DateTime.parse(iso);
    final diff = DateTime.now().difference(DateTime(d.year, d.month, d.day)).inDays;
    if (diff == 1) return 'Yesterday';
    if (diff == 0) return 'Today';
    return DateFormat('EEE d').format(d);
  }

  @override
  Widget build(BuildContext context) {
    final c = SprintColors.of(context);
    final list = t.summaries;
    final s = list.isEmpty ? null : list[selected.clamp(0, list.length - 1)];
    return ListView(
      padding: const EdgeInsets.fromLTRB(14, 10, 14, 24),
      children: [
        // ---- test pull ----
        Container(
          padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
          decoration: BoxDecoration(color: c.card, borderRadius: BorderRadius.circular(14)),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Icon(Icons.science_outlined, size: 18, color: c.muted),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Test: pull yesterday from Teams',
                      style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: c.ink),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 2),
              Text(
                t.busy
                    ? 'Reading yesterday\'s chats (read-only), then summarising on this phone… this can take a minute.'
                    : t.canTestToday
                    ? 'Once a day while we test. Signed in as ${t.account}.'
                    : 'Tested today. The next test is available tomorrow.',
                style: TextStyle(fontSize: 12.5, color: c.muted, height: 1.35),
              ),
              const SizedBox(height: 10),
              if (t.busy)
                const LinearProgressIndicator(minHeight: 4)
              else
                FilledButton.icon(
                  style: FilledButton.styleFrom(minimumSize: const Size(0, 42)),
                  onPressed: t.canTestToday ? _pull : null,
                  icon: Icon(t.canTestToday ? Icons.download_rounded : Icons.check_rounded, size: 18),
                  label: Text(t.canTestToday ? 'Pull yesterday now' : 'Done for today'),
                ),
            ],
          ),
        ),

        if (t.lastError != null) ...[
          const SizedBox(height: 10),
          Container(
            padding: const EdgeInsets.fromLTRB(14, 10, 8, 6),
            decoration: BoxDecoration(color: AppColors.red.withValues(alpha: 0.08), borderRadius: BorderRadius.circular(14)),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'It did not work this time',
                  style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: c.ink),
                ),
                const SizedBox(height: 2),
                Text(t.lastError!, style: TextStyle(fontSize: 12.5, color: c.ink, height: 1.35)),
                Align(
                  alignment: Alignment.centerRight,
                  child: TextButton.icon(
                    onPressed: () => _copyDiagnostics(context),
                    icon: const Icon(Icons.copy_rounded, size: 16),
                    label: const Text('Copy details'),
                  ),
                ),
              ],
            ),
          ),
        ],

        if (list.isEmpty && !t.busy)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 40, 16, 0),
            child: Column(
              children: [
                Icon(Icons.forum_outlined, size: 48, color: c.muted.withValues(alpha: 0.5)),
                const SizedBox(height: 10),
                Text(
                  'No summaries yet.\nTap "Pull yesterday now" to try it.',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 14, color: c.muted, height: 1.4),
                ),
              ],
            ),
          ),

        if (s != null) ...[
          const SizedBox(height: 12),
          SizedBox(
            height: 34,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              itemCount: list.length,
              separatorBuilder: (_, _) => const SizedBox(width: 6),
              itemBuilder: (_, i) => ChoiceChip(
                visualDensity: VisualDensity.compact,
                showCheckmark: false,
                labelStyle: TextStyle(fontSize: 12.5, color: c.ink),
                label: Text(_dayLabel(list[i].date)),
                selected: i == selected,
                onSelected: (_) => setState(() {
                  selected = i;
                  open
                    ..clear()
                    ..add(0);
                }),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(2, 10, 2, 8),
            child: Row(
              children: [
                Icon(Icons.lock_outline_rounded, size: 14, color: c.muted),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    'Summarised ${DateFormat('d MMM, h:mm a').format(DateTime.fromMillisecondsSinceEpoch(s.generatedAt))} on this phone · '
                    '${s.messages} messages · ${s.chats.length} chats · ${s.model}',
                    style: TextStyle(fontSize: 11.5, color: c.muted),
                  ),
                ),
              ],
            ),
          ),
          if (s.highlights.isNotEmpty) _box(c, 'Highlights', c.card, [for (final h in s.highlights) _bullet(c, h, c.done)]),
          if (s.actions.isNotEmpty)
            _box(c, 'Might need your action', Theme.of(context).brightness == Brightness.light ? _actionBg : const Color(0xFF3A2A16), [
              for (final a in s.actions)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 3),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(a.text, style: TextStyle(fontSize: 13.5, color: c.ink, height: 1.35)),
                      Text(a.source, style: TextStyle(fontSize: 11.5, color: c.muted)),
                    ],
                  ),
                ),
            ]),
          if (s.chats.isNotEmpty) ListHeader('By chat', left: 2),
          if (s.chats.isEmpty)
            Padding(
              padding: const EdgeInsets.all(16),
              child: Text('No chat messages found for that day.', style: TextStyle(fontSize: 13.5, color: c.muted)),
            ),
          for (var i = 0; i < s.chats.length; i++) _chatRow(c, i, s.chats[i]),
          Padding(
            padding: const EdgeInsets.fromLTRB(8, 12, 8, 0),
            child: Text(
              'Written on this phone from that day\'s messages. Check details in Teams before acting.',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 11.5, color: c.muted),
            ),
          ),
        ],
      ],
    );
  }

  Widget _box(SprintColors c, String title, Color bg, List<Widget> children) => Container(
    margin: const EdgeInsets.only(bottom: 10),
    padding: const EdgeInsets.fromLTRB(14, 11, 14, 11),
    decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(14)),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: c.ink),
        ),
        const SizedBox(height: 4),
        ...children,
      ],
    ),
  );

  Widget _bullet(SprintColors c, String text, Color dot) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 3),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(top: 6),
          child: Container(
            width: 6,
            height: 6,
            decoration: BoxDecoration(color: dot, shape: BoxShape.circle),
          ),
        ),
        const SizedBox(width: 9),
        Expanded(
          child: Text(text, style: TextStyle(fontSize: 13.5, color: c.ink, height: 1.35)),
        ),
      ],
    ),
  );

  Widget _chatRow(SprintColors c, int i, ({String name, int count, List<String> points}) chat) {
    final isOpen = open.contains(i);
    final initials = chat.name.split(RegExp(r'\s+')).where((w) => w.isNotEmpty).take(2).map((w) => w[0].toUpperCase()).join();
    const palette = [Color(0xFF3E63DD), Color(0xFFD6409F), Color(0xFFF76B15), Color(0xFF12A594), Color(0xFF8E4EC6), Color(0xFF0090FF)];
    return Column(
      children: [
        InkWell(
          onTap: () => setState(() => isOpen ? open.remove(i) : open.add(i)),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 2),
            child: Row(
              children: [
                CircleAvatar(
                  radius: 17,
                  backgroundColor: palette[chat.name.hashCode.abs() % palette.length],
                  child: Text(
                    initials,
                    style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: Colors.white),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              chat.name,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(fontSize: 14.5, color: c.ink, fontWeight: FontWeight.w500),
                            ),
                          ),
                          Text('${chat.count} msgs', style: TextStyle(fontSize: 11.5, color: c.muted)),
                        ],
                      ),
                      if (!isOpen && chat.points.isNotEmpty)
                        Text(
                          chat.points.first,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(fontSize: 12.5, color: c.muted),
                        ),
                    ],
                  ),
                ),
                Icon(isOpen ? Icons.expand_less_rounded : Icons.expand_more_rounded, color: c.muted),
              ],
            ),
          ),
        ),
        if (isOpen)
          Padding(
            padding: const EdgeInsets.fromLTRB(48, 0, 4, 8),
            child: Column(children: [for (final p in chat.points) _bullet(c, p, c.muted)]),
          ),
        Divider(height: 1, color: c.track),
      ],
    );
  }
}

Future<void> _copyDiagnostics(BuildContext context) async {
  await Clipboard.setData(ClipboardData(text: TeamState.instance.diagnosticsText()));
  if (context.mounted) {
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Copied. It contains no message text.')));
  }
}

// ------------------------------------------------------------------ settings

class TeamSettingsScreen extends StatelessWidget {
  const TeamSettingsScreen({super.key});

  String _mask(String id) => id.length < 12 ? id : '${id.substring(0, 4)}…${id.substring(id.length - 4)}';

  Future<bool> _confirm(BuildContext context, String title, String text, String action) async =>
      await showDialog<bool>(
        context: context,
        builder: (c) => AlertDialog(
          title: Text(title),
          content: Text(text),
          actions: [
            TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Cancel')),
            TextButton(
              style: TextButton.styleFrom(foregroundColor: AppColors.red),
              onPressed: () => Navigator.pop(c, true),
              child: Text(action),
            ),
          ],
        ),
      ) ==
      true;

  @override
  Widget build(BuildContext context) {
    final t = TeamState.instance;
    return ListenableBuilder(
      listenable: t,
      builder: (context, _) {
        final c = SprintColors.of(context);
        final allowed = (t.lastDiagnostics['toolsAllowed'] as List?)?.map((e) => e.toString()).toList() ?? const <String>[];
        return Scaffold(
          appBar: AppBar(title: const Text('Team summary settings')),
          body: ListView(
            padding: const EdgeInsets.only(bottom: 24),
            children: [
              Container(
                margin: const EdgeInsets.fromLTRB(14, 12, 14, 4),
                padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
                decoration: BoxDecoration(
                  color: c.done.withValues(alpha: 0.08),
                  border: Border.all(color: c.done.withValues(alpha: 0.35)),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(Icons.verified_user_outlined, size: 22, color: c.ink),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Read-only and on this phone',
                            style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: c.ink),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            'Read-only access (Chat.Read; or read tools only on the MCP server). Summaries are written on the phone and kept '
                            '${TeamState.keepDays} days. Network use: Microsoft sign-in and Microsoft 365 only.',
                            style: TextStyle(fontSize: 12.5, color: c.muted, height: 1.4),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              if (t.mode == 'mcp') const ListHeader('Allowed Teams tools'),
              if (t.mode == 'mcp')
                Padding(
                  padding: const EdgeInsets.fromLTRB(18, 4, 18, 2),
                  child: allowed.isEmpty
                      ? Text('Shown after the first pull.', style: TextStyle(fontSize: 12.5, color: c.muted))
                      : Wrap(
                          spacing: 6,
                          runSpacing: 6,
                          children: [
                            for (final a in allowed)
                              Chip(
                                visualDensity: VisualDensity.compact,
                                avatar: Icon(Icons.check_rounded, size: 14, color: c.ink),
                                label: Text(a, style: const TextStyle(fontSize: 12)),
                              ),
                          ],
                        ),
                ),
              if (t.mode == 'mcp' && t.lastDiagnostics['toolsBlocked'] != null)
                Padding(
                  padding: const EdgeInsets.fromLTRB(18, 6, 18, 0),
                  child: Text(
                    '${t.lastDiagnostics['toolsBlocked']} other tools (posting, editing, deleting…) are blocked in the app.',
                    style: TextStyle(fontSize: 12, color: c.muted),
                  ),
                ),
              const GroupGap(),
              OptionRow(icon: Icons.account_circle_outlined, title: 'Work account', value: t.account ?? 'Not signed in'),
              OptionRow(
                icon: Icons.badge_outlined,
                title: 'Company IDs',
                value: t.configured ? 'Tenant ${_mask(t.tenantId)} · App ${_mask(t.clientId)}' : 'Not set',
              ),
              OptionRow(
                icon: Icons.cable_rounded,
                title: 'Connection',
                value: t.mode == 'mcp' ? 'Company Teams MCP server (read tools only)' : 'Microsoft Graph · Chat.Read (read-only)',
              ),
              OptionRow(
                icon: Icons.memory_rounded,
                title: 'AI model',
                value: t.lastDiagnostics['model']?.toString() ?? 'Chosen on first pull',
              ),
              OptionRow(
                icon: Icons.copy_rounded,
                title: 'Copy connection details',
                value: 'For troubleshooting · contains no message text',
                onTap: () => _copyDiagnostics(context),
              ),
              OptionRow(
                icon: Icons.history_rounded,
                title: 'Kept on phone',
                value:
                    '${t.summaries.length} summar${t.summaries.length == 1 ? 'y' : 'ies'} · older than ${TeamState.keepDays} days delete themselves',
              ),
              OptionRow(
                icon: Icons.delete_outline_rounded,
                color: AppColors.red,
                title: 'Delete all summaries',
                onTap: () async {
                  if (await _confirm(context, 'Delete all summaries?', 'They are removed from this phone.', 'Delete')) {
                    await t.deleteSummaries();
                  }
                },
              ),
              OptionRow(
                icon: Icons.logout_rounded,
                color: AppColors.red,
                title: 'Sign out and remove',
                value: 'Disconnects Teams and deletes the IDs and summaries',
                onTap: () async {
                  if (await _confirm(
                    context,
                    'Sign out and remove?',
                    'Team summary is disconnected and everything about it is deleted from this phone.',
                    'Remove',
                  )) {
                    await t.removeAll();
                    if (context.mounted) Navigator.of(context).popUntil((r) => r.isFirst);
                  }
                },
              ),
            ],
          ),
        );
      },
    );
  }
}

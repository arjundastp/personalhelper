import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';

import '../models.dart' show isoDate;

/// One day's Team summary, as produced on the phone by the native side (Team.kt).
class TeamSummary {
  final String date; // the day summarised (yyyy-MM-dd)
  final int generatedAt;
  final List<String> highlights;
  final List<({String text, String source})> actions;
  final List<({String name, int count, List<String> points})> chats;
  final Map<String, dynamic> diagnostics;
  final bool partial; // "today so far" (notifications mode)

  TeamSummary.fromJson(Map<String, dynamic> j)
    : date = j['date'] as String,
      generatedAt = (j['generatedAt'] as num?)?.toInt() ?? 0,
      highlights = ((j['highlights'] as List?) ?? const []).map((e) => e.toString()).toList(),
      actions = ((j['actions'] as List?) ?? const []).map((e) => (text: (e as Map)['text']?.toString() ?? '', source: e['source']?.toString() ?? '')).toList(),
      chats = ((j['chats'] as List?) ?? const [])
          .map(
            (e) => (
              name: (e as Map)['name']?.toString() ?? 'Chat',
              count: (e['count'] as num?)?.toInt() ?? 0,
              points: ((e['points'] as List?) ?? const []).map((p) => p.toString()).toList(),
            ),
          )
          .toList(),
      diagnostics = Map<String, dynamic>.from((j['diagnostics'] as Map?) ?? const {}),
      partial = j['partial'] as bool? ?? false;

  int get messages => (diagnostics['messages'] as num?)?.toInt() ?? chats.fold(0, (s, c) => s + c.count);
  String get model => diagnostics['model']?.toString() ?? '';
}

/// Team summary: reads yesterday in Microsoft Teams (read-only) and summarises it on the phone.
/// The tenant and client IDs are typed in by the user and stored only on this phone.
class TeamState extends ChangeNotifier {
  TeamState._();
  static final TeamState instance = TeamState._();
  static const _ch = MethodChannel('remindly/native');
  static const keepDays = 10;

  bool enabled = false;
  String tenantId = '';
  String clientId = '';

  /// 'notifications' (Teams notifications on this phone, no sign-in), 'graph' (Microsoft Graph, Chat.Read)
  /// or 'mcp' (company Teams MCP server).
  String mode = 'notifications';
  String endpointUrl = ''; // endpoint mode: e.g. https://daymate-summary.<you>.workers.dev
  String readKey = ''; // endpoint mode: READ_KEY of the Worker (stored only on this phone)
  int lastFetched = 0;
  bool notifAccess = false;
  bool teamsInstalled = true;
  int collectedToday = 0;
  String scope = ''; // MCP only; empty = app default (shared Agent 365 Tools, Teams scope)
  String serverUrl = ''; // empty = app default Teams MCP server address
  String? account;
  String? lastTestPull; // yyyy-MM-dd of the last manual test pull (limited to once a day)
  Map<String, dynamic> lastDiagnostics = {};
  String? lastError;
  List<Map<String, dynamic>> _summaries = [];
  bool busy = false;

  bool get configured => tenantId.isNotEmpty && clientId.isNotEmpty;
  bool get viaNotifications => mode == 'notifications';

  /// Ready to show summaries: notification access granted, or signed in to Microsoft.
  bool get viaEndpoint => mode == 'endpoint';
  bool get ready => switch (mode) {
    'notifications' => notifAccess,
    'endpoint' => endpointUrl.isNotEmpty && readKey.isNotEmpty,
    _ => configured && account != null,
  };
  bool get signedIn => account != null;
  String get today => isoDate(DateTime.now());
  bool get canTestToday => lastTestPull != today;

  /// Newest first, at most [keepDays].
  List<TeamSummary> get summaries => _summaries.map(TeamSummary.fromJson).toList()..sort((a, b) => b.date.compareTo(a.date));

  Map<String, dynamic> toJson() => {
    'enabled': enabled,
    'tenantId': tenantId,
    'clientId': clientId,
    'mode': mode,
    'endpointUrl': endpointUrl,
    'readKey': readKey,
    'lastFetched': lastFetched,
    'scope': scope,
    'serverUrl': serverUrl,
    'account': account,
    'lastTestPull': lastTestPull,
    'lastDiagnostics': lastDiagnostics,
    'lastError': lastError,
    'summaries': _summaries,
  };

  void fromJson(Map<String, dynamic> j) {
    enabled = j['enabled'] as bool? ?? false;
    tenantId = j['tenantId'] as String? ?? '';
    clientId = j['clientId'] as String? ?? '';
    mode = j['mode'] as String? ?? 'notifications';
    endpointUrl = j['endpointUrl'] as String? ?? '';
    readKey = j['readKey'] as String? ?? '';
    lastFetched = (j['lastFetched'] as num?)?.toInt() ?? 0;
    scope = j['scope'] as String? ?? '';
    serverUrl = j['serverUrl'] as String? ?? '';
    account = j['account'] as String?;
    lastTestPull = j['lastTestPull'] as String?;
    lastDiagnostics = Map<String, dynamic>.from((j['lastDiagnostics'] as Map?) ?? const {});
    lastError = j['lastError'] as String?;
    _summaries = ((j['summaries'] as List?) ?? const []).map((e) => Map<String, dynamic>.from(e as Map)).toList();
    _prune();
  }

  Future<void> load() async {
    try {
      fromJson(jsonDecode(await _ch.invokeMethod<String>('getTeam') ?? '{}') as Map<String, dynamic>);
    } catch (_) {}
    await refreshNotifications(notify: false);
    notifyListeners();
  }

  // ---------------- notifications mode ----------------

  Future<void> refreshNotifications({bool notify = true}) async {
    try {
      final r = jsonDecode(await _ch.invokeMethod<String>('teamNotifStatus') ?? '{}') as Map<String, dynamic>;
      notifAccess = r['access'] as bool? ?? false;
      collectedToday = (r['today'] as num?)?.toInt() ?? 0;
      teamsInstalled = r['teamsInstalled'] as bool? ?? true;
    } catch (_) {}
    if (notify) notifyListeners();
  }

  Future<void> setMode(String m) async {
    mode = m;
    await save();
  }

  /// Opens Android's "Notification access" page for DayMate.
  Future<void> openNotificationAccess() async {
    await setMode('notifications');
    await _ch.invokeMethod('teamNotifSettings');
  }

  /// Summarises collected Teams notifications (no network). No daily limit: it is all on the phone.
  Future<String?> summariseNotifications({required bool today}) async {
    busy = true;
    lastError = null;
    notifyListeners();
    try {
      final r = jsonDecode(await _ch.invokeMethod<String>('teamPullNotifications', today) ?? '{}') as Map<String, dynamic>;
      if (r['ok'] != true) {
        lastError = r['error']?.toString() ?? 'Something went wrong';
        return lastError;
      }
      lastDiagnostics = Map<String, dynamic>.from((r['diagnostics'] as Map?) ?? const {});
      r.remove('ok');
      _summaries.removeWhere((s) => s['date'] == r['date']);
      _summaries.add(r);
      _prune();
      return null;
    } catch (e) {
      lastError = '$e';
      return lastError;
    } finally {
      busy = false;
      await save();
    }
  }

  // ---------------- endpoint mode (Claude routine → Cloudflare Worker → DayMate) ----------------

  static String? checkEndpoint(String url) {
    final u = Uri.tryParse(url.trim());
    if (u == null || u.scheme != 'https' || u.host.isEmpty) return 'The address must start with https://';
    return null;
  }

  /// Saves the endpoint address and read key, then tries a fetch. Returns null on success.
  Future<String?> connectEndpoint(String url, String key) async {
    endpointUrl = url.trim().replaceAll(RegExp(r'/+$'), '');
    readKey = key.trim();
    mode = 'endpoint';
    await save();
    return fetchFromEndpoint();
  }

  /// Downloads the last [keepDays] days of summaries from the endpoint (read key only).
  Future<String?> fetchFromEndpoint() async {
    if (endpointUrl.isEmpty || readKey.isEmpty) return 'Endpoint not set up';
    busy = true;
    lastError = null;
    notifyListeners();
    final client = HttpClient()..connectionTimeout = const Duration(seconds: 20);
    try {
      final since = isoDate(DateTime.now().subtract(const Duration(days: keepDays)));
      final req = await client.getUrl(Uri.parse('$endpointUrl/summaries?since=$since'));
      req.headers.set(HttpHeaders.authorizationHeader, 'Bearer $readKey');
      req.headers.set(HttpHeaders.acceptHeader, 'application/json');
      final res = await req.close().timeout(const Duration(seconds: 30));
      final body = await res.transform(utf8.decoder).join();
      if (res.statusCode == 401) throw 'The read key was not accepted (401). Check READ_KEY.';
      if (res.statusCode != 200) {
        throw 'Endpoint answered ${res.statusCode}: ${body.length > 160 ? body.substring(0, 160) : body}';
      }
      final list = (jsonDecode(body) as List).whereType<Map>().map((e) => Map<String, dynamic>.from(e)).toList();
      for (final s in list) {
        if (s['date'] is! String) continue;
        s['generatedAt'] ??= s['receivedAt'] ?? DateTime.now().millisecondsSinceEpoch;
        _summaries.removeWhere((x) => x['date'] == s['date']);
        _summaries.add(s);
      }
      _prune();
      lastFetched = DateTime.now().millisecondsSinceEpoch;
      if (list.isNotEmpty) lastDiagnostics = Map<String, dynamic>.from((list.first['diagnostics'] as Map?) ?? const {});
      return null;
    } catch (e) {
      lastError = e is String ? e : 'Could not reach the endpoint: $e';
      return lastError;
    } finally {
      client.close(force: true);
      busy = false;
      await save();
    }
  }

  /// Fetch when the tab opens, at most every 30 minutes.
  Future<void> maybeAutoFetch() async {
    if (!enabled || !viaEndpoint || busy) return;
    if (DateTime.now().millisecondsSinceEpoch - lastFetched < 30 * 60 * 1000) return;
    await fetchFromEndpoint();
  }

  Future<void> clearCollected() async {
    try {
      await _ch.invokeMethod('teamNotifClear');
    } catch (_) {}
    await refreshNotifications();
  }

  Future<void> save() async {
    notifyListeners();
    try {
      await _ch.invokeMethod('saveTeam', jsonEncode(toJson()));
    } catch (_) {}
  }

  /// Keeps only the last [keepDays] days of summaries.
  void _prune() {
    final cutoff = isoDate(DateTime.now().subtract(const Duration(days: keepDays)));
    _summaries.removeWhere((s) => (s['date'] as String? ?? '').compareTo(cutoff) < 0);
  }

  Future<void> setEnabled(bool on) async {
    enabled = on;
    await save();
  }

  static final _guid = RegExp(r'^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$');
  static bool validId(String v) => _guid.hasMatch(v.trim());

  static const defaultScope = 'ea9ffc3e-8a23-4a7d-836d-234d7c7565c1/McpServers.Teams.All';
  static const defaultServer = 'https://agent365.svc.cloud.microsoft/agents/tenants/{tenantId}/servers/mcp_TeamsServer';

  Future<void> setIds(String tenant, String client, {String? mode, String? scope, String? serverUrl}) async {
    final s = (scope ?? this.scope).trim();
    final u = (serverUrl ?? this.serverUrl).trim();
    final m = mode ?? this.mode;
    final changed = tenant.trim() != tenantId || client.trim() != clientId || s != this.scope || m != this.mode;
    this.mode = m;
    tenantId = tenant.trim();
    clientId = client.trim();
    this.scope = s == defaultScope ? '' : s;
    this.serverUrl = u == defaultServer ? '' : u;
    if (changed) account = null; // a different registration needs a fresh sign-in
    await save();
  }

  /// Opens Microsoft sign-in. Returns null on success, else an error message.
  Future<String?> signIn() async {
    busy = true;
    notifyListeners();
    try {
      final r = jsonDecode(await _ch.invokeMethod<String>('teamSignIn') ?? '{}') as Map<String, dynamic>;
      if (r['ok'] == true) {
        account = r['account'] as String?;
        lastError = null;
        return null;
      }
      return r['error']?.toString() ?? 'Sign-in failed';
    } catch (e) {
      return '$e';
    } finally {
      busy = false;
      await save();
    }
  }

  Future<void> signOut() async {
    try {
      await _ch.invokeMethod('teamSignOut');
    } catch (_) {}
    account = null;
    await save();
  }

  /// Test pull: reads yesterday and summarises it. Allowed once per day.
  /// Returns null on success, else an error message.
  Future<String?> pullYesterday() async {
    if (!canTestToday) return 'Already tested today. Try again tomorrow.';
    busy = true;
    lastError = null;
    notifyListeners();
    try {
      final r = jsonDecode(await _ch.invokeMethod<String>('teamPull') ?? '{}') as Map<String, dynamic>;
      lastTestPull = today; // counts even if it failed, to respect the once-a-day limit
      if (r['ok'] != true) {
        lastError = r['error']?.toString() ?? 'Something went wrong';
        return lastError;
      }
      lastDiagnostics = Map<String, dynamic>.from((r['diagnostics'] as Map?) ?? const {});
      r.remove('ok');
      _summaries.removeWhere((s) => s['date'] == r['date']);
      _summaries.add(r);
      _prune();
      return null;
    } catch (e) {
      lastError = '$e';
      return lastError;
    } finally {
      busy = false;
      await save();
    }
  }

  Future<void> deleteSummaries() async {
    _summaries.clear();
    await save();
  }

  /// Sign out and forget everything about Teams on this phone.
  Future<void> removeAll() async {
    await signOut();
    tenantId = '';
    clientId = '';
    scope = '';
    serverUrl = '';
    endpointUrl = '';
    readKey = '';
    lastFetched = 0;
    lastTestPull = null;
    lastDiagnostics = {};
    lastError = null;
    _summaries.clear();
    enabled = false;
    mode = 'notifications';
    try {
      await _ch.invokeMethod('teamNotifClear');
    } catch (_) {}
    await save();
  }

  /// Text to share when asking for help: no message content, IDs masked.
  String diagnosticsText() {
    final d = lastDiagnostics;
    return [
      'DayMate Team summary – connection check',
      'Date: ${lastTestPull ?? '-'}',
      'Result: ${lastError == null ? 'OK' : 'Error – $lastError'}',
      'Connection: ${viaEndpoint
          ? 'Endpoint ${Uri.tryParse(endpointUrl)?.host ?? '-'}'
          : viaNotifications
          ? 'Teams notifications on this phone (access ${notifAccess ? 'on' : 'off'}, $collectedToday collected today)'
          : (mode == 'mcp' ? 'Teams MCP server · permission ${scope.isEmpty ? 'default' : scope} · server ${serverUrl.isEmpty ? 'default' : 'custom'}' : 'Microsoft Graph (Chat.Read)')}',
      'Tools on server: ${d['toolsTotal'] ?? '-'} (read-only allowed: ${(d['toolsAllowed'] as List?)?.length ?? '-'}, blocked: ${d['toolsBlocked'] ?? '-'})',
      'Allowed tools: ${(d['toolsAllowed'] as List?)?.join(', ') ?? '-'}',
      'Chat tool: ${d['chatTool'] ?? '-'} · Message tool: ${d['messageTool'] ?? '-'}',
      'Chats listed: ${d['chatsListed'] ?? '-'} · With messages yesterday: ${d['chatsWithMessages'] ?? '-'} · Messages: ${d['messages'] ?? '-'}',
      'AI: ${d['model'] ?? '-'} · Took ${d['seconds'] ?? '-'} s',
    ].join('\n');
  }
}

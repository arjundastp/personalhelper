import 'dart:convert';

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

  TeamSummary.fromJson(Map<String, dynamic> j)
      : date = j['date'] as String,
        generatedAt = (j['generatedAt'] as num?)?.toInt() ?? 0,
        highlights = ((j['highlights'] as List?) ?? const []).map((e) => e.toString()).toList(),
        actions = ((j['actions'] as List?) ?? const [])
            .map((e) => (text: (e as Map)['text']?.toString() ?? '', source: e['source']?.toString() ?? ''))
            .toList(),
        chats = ((j['chats'] as List?) ?? const [])
            .map((e) => (
                  name: (e as Map)['name']?.toString() ?? 'Chat',
                  count: (e['count'] as num?)?.toInt() ?? 0,
                  points: ((e['points'] as List?) ?? const []).map((p) => p.toString()).toList(),
                ))
            .toList(),
        diagnostics = Map<String, dynamic>.from((j['diagnostics'] as Map?) ?? const {});

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
  String scope = ''; // empty = app default (shared Agent 365 Tools, Teams scope)
  String serverUrl = ''; // empty = app default Teams MCP server address
  String? account;
  String? lastTestPull; // yyyy-MM-dd of the last manual test pull (limited to once a day)
  Map<String, dynamic> lastDiagnostics = {};
  String? lastError;
  List<Map<String, dynamic>> _summaries = [];
  bool busy = false;

  bool get configured => tenantId.isNotEmpty && clientId.isNotEmpty;
  bool get signedIn => account != null;
  String get today => isoDate(DateTime.now());
  bool get canTestToday => lastTestPull != today;

  /// Newest first, at most [keepDays].
  List<TeamSummary> get summaries =>
      _summaries.map(TeamSummary.fromJson).toList()..sort((a, b) => b.date.compareTo(a.date));

  Map<String, dynamic> toJson() => {
        'enabled': enabled,
        'tenantId': tenantId,
        'clientId': clientId,
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
    notifyListeners();
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

  Future<void> setIds(String tenant, String client, {String? scope, String? serverUrl}) async {
    final s = (scope ?? this.scope).trim();
    final u = (serverUrl ?? this.serverUrl).trim();
    final changed = tenant.trim() != tenantId || client.trim() != clientId || s != this.scope;
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
    lastTestPull = null;
    lastDiagnostics = {};
    lastError = null;
    _summaries.clear();
    enabled = false;
    await save();
  }

  /// Text to share when asking for help: no message content, IDs masked.
  String diagnosticsText() {
    final d = lastDiagnostics;
    return [
      'DayMate Team summary – connection check',
      'Date: ${lastTestPull ?? '-'}',
      'Result: ${lastError == null ? 'OK' : 'Error – $lastError'}',
      'Permission: ${scope.isEmpty ? 'default' : scope} · Server: ${serverUrl.isEmpty ? 'default' : 'custom'}',
      'Tools on server: ${d['toolsTotal'] ?? '-'} (read-only allowed: ${(d['toolsAllowed'] as List?)?.length ?? '-'}, blocked: ${d['toolsBlocked'] ?? '-'})',
      'Allowed tools: ${(d['toolsAllowed'] as List?)?.join(', ') ?? '-'}',
      'Chat tool: ${d['chatTool'] ?? '-'} · Message tool: ${d['messageTool'] ?? '-'}',
      'Chats listed: ${d['chatsListed'] ?? '-'} · With messages yesterday: ${d['chatsWithMessages'] ?? '-'} · Messages: ${d['messages'] ?? '-'}',
      'AI: ${d['model'] ?? '-'} · Took ${d['seconds'] ?? '-'} s',
    ].join('\n');
  }
}

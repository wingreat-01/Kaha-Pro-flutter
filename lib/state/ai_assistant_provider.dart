import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// A message in the wire-format sense: covers plain user/assistant
/// chat turns as well as the hidden assistant tool_calls / tool
/// result messages the edge function now returns as part of
/// `turn_messages`. Only 'user' and plain-content 'assistant'
/// messages are ever shown as chat bubbles -- see [isVisibleInChat].
class ChatMessage {
  final String role; // 'user' | 'assistant' | 'tool'
  final String? content; // null on an assistant tool_calls message
  final DateTime timestamp;
  final String? provider; // which AI provider answered (final assistant msg only)
  final List<Map<String, dynamic>>? toolCalls; // present on assistant tool-call messages
  final String? toolCallId; // present on 'tool' role messages
  final String? name; // tool name, present on 'tool' role messages

  ChatMessage({
    required this.role,
    required this.content,
    required this.timestamp,
    this.provider,
    this.toolCalls,
    this.toolCallId,
    this.name,
  });

  /// True for messages that belong in the chat UI. Tool-call/tool-result
  /// plumbing is kept in history (so the model can see its own prior
  /// tool-call arguments on the next turn) but never shown to the user.
  bool get isVisibleInChat =>
      role == 'user' || (role == 'assistant' && content != null && content!.isNotEmpty);

  Map<String, dynamic> toJson() => {
        'role': role,
        'content': content,
        'timestamp': timestamp.toIso8601String(),
        'provider': provider,
        if (toolCalls != null) 'tool_calls': toolCalls,
        if (toolCallId != null) 'tool_call_id': toolCallId,
        if (name != null) 'name': name,
      };

  factory ChatMessage.fromJson(Map<String, dynamic> json) => ChatMessage(
        role: json['role'] as String? ?? 'user',
        content: json['content'] as String?,
        timestamp: DateTime.parse(json['timestamp'] as String),
        provider: json['provider'] as String?,
        toolCalls: (json['tool_calls'] as List<dynamic>?)
            ?.map((e) => Map<String, dynamic>.from(e as Map))
            .toList(),
        toolCallId: json['tool_call_id'] as String?,
        name: json['name'] as String?,
      );

  /// Built from a `turn_messages` entry returned by the edge function
  /// (same shape it sent to the provider internally: role/content plus
  /// optional tool_calls / tool_call_id / name).
  factory ChatMessage.fromTurnMessage(Map<String, dynamic> json, {String? provider}) =>
      ChatMessage(
        role: json['role'] as String? ?? 'assistant',
        content: json['content'] as String?,
        timestamp: DateTime.now(),
        provider: provider,
        toolCalls: (json['tool_calls'] as List<dynamic>?)
            ?.map((e) => Map<String, dynamic>.from(e as Map))
            .toList(),
        toolCallId: json['tool_call_id'] as String?,
        name: json['name'] as String?,
      );

  /// The shape sent back to the edge function -- includes the raw
  /// tool-call plumbing fields, not just role/content.
  Map<String, dynamic> toWireJson() => {
        'role': role,
        'content': content,
        if (toolCalls != null) 'tool_calls': toolCalls,
        if (toolCallId != null) 'tool_call_id': toolCallId,
        if (name != null) 'name': name,
      };
}

/// Talks to the `ai-assistant` Supabase edge function and keeps a
/// local, persisted chat history for the AI Assistant tab (owner/admin
/// only -- see home_shell.dart).
///
/// The edge function runs a real tool-calling loop server-side (system
/// prompt + tool schemas live there) and now hands back the structured
/// messages it generated each turn (`turn_messages`: assistant
/// tool_calls, tool results, final assistant text) instead of just a
/// flattened reply string. This provider persists and resends that
/// structured history so a two-step tool flow like withdraw_inventory's
/// confirm step still has its item_id/quantity available on the
/// follow-up turn, instead of the model having to reconstruct them from
/// plain chat text (which doesn't contain IDs).
class AiAssistantProvider extends ChangeNotifier {
  static const _storageKey = 'ai_assistant_history_v1';
  static const _maxStored = 30; // messages kept on disk / shown in UI
  static const _recentForContext = 3; // last N *turns* sent verbatim (a turn = 1 user msg + everything up to the next one)
  static const _summarizeEvery = 10; // fold older turns into the summary every N new visible messages

  final SupabaseClient _client = Supabase.instance.client;

  final List<ChatMessage> _messages = [];
  String _summary = '';
  bool isSending = false;
  bool isLoaded = false;
  String? error;
  int _sinceLastSummary = 0;

  /// Only the messages meant to be rendered as chat bubbles -- hidden
  /// tool_calls/tool plumbing is filtered out here, not at storage time,
  /// since the raw messages still need to be persisted for resending.
  List<ChatMessage> get messages =>
      List.unmodifiable(_messages.where((m) => m.isVisibleInChat));

  Future<void> loadFromDisk() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_storageKey);
    if (raw != null) {
      try {
        final decoded = jsonDecode(raw) as Map<String, dynamic>;
        final list = (decoded['messages'] as List<dynamic>? ?? [])
            .map((m) => ChatMessage.fromJson(m as Map<String, dynamic>))
            .toList();
        _messages
          ..clear()
          ..addAll(list);
        _summary = decoded['summary'] as String? ?? '';
      } catch (_) {
        // Corrupt/old-format cache -- start clean rather than crash.
      }
    }
    isLoaded = true;
    notifyListeners();
  }

  Future<void> _persist() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      _storageKey,
      jsonEncode({
        'messages': _messages.map((m) => m.toJson()).toList(),
        'summary': _summary,
      }),
    );
  }

  /// Builds the `messages` array sent to the edge function: an
  /// optional summary turn for older context, the last few *whole
  /// turns* verbatim (including any hidden tool_calls/tool messages),
  /// then the new message.
  ///
  /// Windowing by turn rather than raw message count matters here: a
  /// withdraw_inventory confirmation round-trip is a user message plus
  /// a hidden assistant tool_calls message and a hidden tool result.
  /// Cutting the window mid-turn would strand that tool_calls message
  /// without its result (or vice versa), and more importantly would
  /// drop the item_id the model needs to resolve "yes, confirm" on the
  /// very next message.
  List<Map<String, dynamic>> _composeMessages(String newUserMessage) {
    final userIndices = <int>[
      for (var i = 0; i < _messages.length; i++)
        if (_messages[i].role == 'user') i,
    ];
    final startIdx = userIndices.length > _recentForContext
        ? userIndices[userIndices.length - _recentForContext]
        : 0;
    final recent = _messages.sublist(startIdx);

    final out = <Map<String, dynamic>>[];
    if (_summary.isNotEmpty) {
      out.add({'role': 'user', 'content': 'Earlier conversation summary (for context only): $_summary'});
    }
    for (final m in recent) {
      out.add(m.toWireJson());
    }
    out.add({'role': 'user', 'content': newUserMessage});
    return out;
  }

  /// Sends [text] to the edge function. Returns the server's real
  /// remaining-credit count on success so the caller (AiAssistantScreen)
  /// can set StoreProvider's count to that exact value -- or null on
  /// failure, in which case nothing about credits should be touched.
  Future<int?> sendMessage(String text) async {
    final trimmed = text.trim();
    if (trimmed.isEmpty || isSending) return null;

    error = null;
    isSending = true;
    _messages.add(ChatMessage(role: 'user', content: trimmed, timestamp: DateTime.now()));
    notifyListeners();

    try {
      final res = await _client.functions.invoke(
        'ai-assistant',
        body: {'messages': _composeMessages(trimmed)},
      );

      final data = res.data;
      final reply = data is Map ? data['response'] as String? : null;
      final providerUsed = data is Map ? data['provider'] as String? : null;
      final creditsRemaining = data is Map ? data['credits_remaining'] as int? : null;
      final turnMessages = data is Map ? data['turn_messages'] as List<dynamic>? : null;
      if (reply == null || reply.isEmpty) {
        throw Exception('Empty response from assistant.');
      }

      if (turnMessages != null && turnMessages.isNotEmpty) {
        // Structured path: append every message the server generated
        // this turn (tool_calls, tool results, final assistant text) so
        // the next request can resend them verbatim.
        var visibleAdded = 0;
        for (final raw in turnMessages) {
          final m = ChatMessage.fromTurnMessage(
            Map<String, dynamic>.from(raw as Map),
            provider: providerUsed,
          );
          _messages.add(m);
          if (m.isVisibleInChat) visibleAdded++;
        }
        _sinceLastSummary += 1 + visibleAdded; // the user turn plus any visible assistant replies
      } else {
        // Fallback for an older/unexpected server response shape --
        // still works, just loses tool-call state across turns as before.
        _messages.add(ChatMessage(
          role: 'assistant',
          content: reply,
          timestamp: DateTime.now(),
          provider: providerUsed,
        ));
        _sinceLastSummary += 2;
      }

      _trimToTurnBoundary();

      if (_sinceLastSummary >= _summarizeEvery) {
        _refreshSummary();
        _sinceLastSummary = 0;
      }

      await _persist();
      isSending = false;
      notifyListeners();
      return creditsRemaining;
    } on FunctionException catch (e) {
      isSending = false;
      error = e.status == 403
          ? 'No AI credits remaining this month. Upgrade or wait for next cycle.'
          : 'Assistant is temporarily unavailable. Please try again.';
      notifyListeners();
      return null;
    } catch (_) {
      isSending = false;
      error = 'Assistant is temporarily unavailable. Please try again.';
      notifyListeners();
      return null;
    }
  }

  /// Trims stored messages down toward [_maxStored], but only ever cuts
  /// at a 'user' message boundary -- never mid-turn -- so a trimmed
  /// history can't strand a tool_calls message without its result.
  void _trimToTurnBoundary() {
    if (_messages.length <= _maxStored) return;
    final target = _messages.length - _maxStored;
    var cut = target;
    while (cut < _messages.length && _messages[cut].role != 'user') {
      cut++;
    }
    if (cut > 0 && cut < _messages.length) {
      _messages.removeRange(0, cut);
    }
  }

  /// Cheap local resummarization -- no extra AI call or credit spent
  /// just to compress history. Folds the topics of the portion of the
  /// window about to scroll out of "recent" into a short running
  /// summary line, so context sent per request stays bounded even
  /// after hundreds of turns.
  void _refreshSummary() {
    final userIndices = <int>[
      for (var i = 0; i < _messages.length; i++)
        if (_messages[i].role == 'user') i,
    ];
    final startIdx = userIndices.length > _recentForContext
        ? userIndices[userIndices.length - _recentForContext]
        : 0;
    final older = _messages.sublist(0, startIdx);
    if (older.isEmpty) return;
    final topics = older
        .where((m) => m.role == 'user')
        .map((m) => m.content ?? '')
        .where((c) => c.isNotEmpty)
        .take(5)
        .join('; ');
    if (topics.isEmpty) return;
    _summary = _summary.isEmpty
        ? 'Owner previously asked about: $topics.'
        : '$_summary Also asked about: $topics.';
  }

  Future<void> clearHistory() async {
    _messages.clear();
    _summary = '';
    _sinceLastSummary = 0;
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_storageKey);
    notifyListeners();
  }
}

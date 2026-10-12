import 'package:dio/dio.dart';

import '../core/api_client.dart';
import '../models/ai.dart';
import 'api_exception.dart';

/// Client for the shared AI assistant API (`/api/ai/*`) — the SAME backend, tools, permissions and tenant/branch
/// scope as the web widget. Every call identifies itself as the mobile channel so the server returns app deep-links.
class AiService {
  AiService(this._api);
  final ApiClient _api;

  static final Options _mobile = Options(headers: {'X-Client': 'mobile'});

  /// Whether the assistant is available to this user (+ starter prompts). A 403 (disabled / no permission) or a
  /// network failure means "not available" — the entry points simply stay hidden.
  Future<AiState> state({AiPageContext? context}) async {
    try {
      final res = await _api.dio.get('/api/ai/state', queryParameters: context?.toQuery(), options: _mobile);
      if (!isOk(res) || res.data is! Map) return AiState.disabled;
      return AiState.fromJson(res.data as Map<String, dynamic>);
    } catch (_) {
      return AiState.disabled;
    }
  }

  Future<List<AiCapability>> capabilities() async {
    final res = await _api.dio.get('/api/ai/capabilities', options: _mobile);
    if (!isOk(res)) throw ApiException.from(res);
    return (res.data as List).map((e) => AiCapability.fromJson(e as Map<String, dynamic>)).toList();
  }

  Future<AiChatReply> chat(String message, {String? conversationId, AiPageContext? context}) async {
    final res = await _api.dio.post('/api/ai/chat',
        data: {
          'conversationId': ?conversationId,
          'message': message,
          if (context != null) 'context': context.toJson(),
          'channel': 'mobile',
        },
        options: _mobile);
    if (!isOk(res)) throw ApiException.from(res);
    return AiChatReply.fromJson(res.data as Map<String, dynamic>);
  }

  /// Execute a write the assistant proposed — only after the user tapped Confirm.
  Future<AiChatReply> confirm(String token, {String? conversationId}) async {
    final res = await _api.dio.post('/api/ai/actions/confirm',
        data: {'token': token, 'conversationId': ?conversationId, 'channel': 'mobile'}, options: _mobile);
    if (!isOk(res)) throw ApiException.from(res);
    return AiChatReply.fromJson(res.data as Map<String, dynamic>);
  }

  Future<List<AiConversation>> conversations() async {
    final res = await _api.dio.get('/api/ai/conversations', options: _mobile);
    if (!isOk(res)) throw ApiException.from(res);
    return (res.data as List).map((e) => AiConversation.fromJson(e as Map<String, dynamic>)).toList();
  }

  Future<List<AiMessage>> messages(String conversationId) async {
    final res = await _api.dio.get('/api/ai/conversations/$conversationId', options: _mobile);
    if (!isOk(res)) throw ApiException.from(res);
    return (res.data as List).map((e) => AiMessage.fromJson(e as Map<String, dynamic>)).toList();
  }

  Future<void> deleteConversation(String conversationId) async {
    final res = await _api.dio.delete('/api/ai/conversations/$conversationId', options: _mobile);
    if (!isOk(res) && res.statusCode != 404) throw ApiException.from(res);
  }
}

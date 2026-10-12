// Models for the shared AI assistant API (`/api/ai/*`) — the same backend the web widget uses.

class AiState {
  AiState({required this.enabled, required this.suggestions});
  final bool enabled;
  final List<String> suggestions;

  factory AiState.fromJson(Map<String, dynamic> j) => AiState(
        enabled: j['enabled'] as bool? ?? false,
        suggestions: _strings(j['suggestions']),
      );

  static AiState get disabled => AiState(enabled: false, suggestions: const []);
}

/// The screen the assistant was opened from (an untrusted hint the server re-validates).
class AiPageContext {
  const AiPageContext({this.module, this.route, this.recordType, this.recordId});
  final String? module;
  final String? route;
  final String? recordType;
  final String? recordId;

  Map<String, dynamic> toJson() => {
        if (module != null) 'module': module,
        if (route != null) 'route': route,
        if (recordType != null) 'recordType': recordType,
        if (recordId != null) 'recordId': recordId,
      };

  Map<String, dynamic> toQuery() => {
        if (module != null) 'module': module,
        if (recordType != null) 'recordType': recordType,
        if (recordId != null) 'recordId': recordId,
      };
}

class AiLink {
  AiLink({required this.label, required this.kind, this.id, this.webUrl, this.mobileRoute});
  final String label;
  final String kind;
  final String? id;
  final String? webUrl;
  final String? mobileRoute;

  factory AiLink.fromJson(Map<String, dynamic> j) => AiLink(
        label: j['label'] as String? ?? '',
        kind: j['kind'] as String? ?? 'screen',
        id: j['id'] as String?,
        webUrl: j['webUrl'] as String?,
        mobileRoute: j['mobileRoute'] as String?,
      );
}

class AiPendingAction {
  AiPendingAction({required this.token, required this.tool, required this.title, required this.summary, required this.destructive});
  final String token;
  final String tool;
  final String title;
  final String summary;
  final bool destructive;

  factory AiPendingAction.fromJson(Map<String, dynamic> j) => AiPendingAction(
        token: j['token'] as String? ?? '',
        tool: j['tool'] as String? ?? '',
        title: j['title'] as String? ?? '',
        summary: j['summary'] as String? ?? '',
        destructive: j['destructive'] as bool? ?? false,
      );
}

class AiChatReply {
  AiChatReply({
    required this.conversationId,
    required this.answer,
    required this.mode,
    required this.toolsUsed,
    required this.suggestions,
    required this.links,
    this.navigationUrl,
    this.navigationLabel,
    this.pendingAction,
  });
  final String conversationId;
  final String answer;
  final int mode; // 0 = fallback (in-house), 1 = provider
  final List<String> toolsUsed;
  final List<String> suggestions;
  final List<AiLink> links;
  final String? navigationUrl;
  final String? navigationLabel;
  final AiPendingAction? pendingAction;

  bool get requiresConfirmation => pendingAction != null;

  /// Links the mobile app can actually open (web-only links are dropped).
  List<AiLink> get mobileLinks => links.where((l) => l.mobileRoute != null && l.mobileRoute!.isNotEmpty).toList();

  factory AiChatReply.fromJson(Map<String, dynamic> j) => AiChatReply(
        conversationId: j['conversationId'] as String? ?? '',
        answer: j['answer'] as String? ?? '',
        mode: (j['mode'] as num?)?.toInt() ?? 0,
        toolsUsed: _strings(j['toolsUsed']),
        suggestions: _strings(j['suggestions']),
        links: (j['links'] as List? ?? const []).map((e) => AiLink.fromJson(e as Map<String, dynamic>)).toList(),
        navigationUrl: j['navigationUrl'] as String?,
        navigationLabel: j['navigationLabel'] as String?,
        pendingAction: j['pendingAction'] is Map ? AiPendingAction.fromJson(j['pendingAction'] as Map<String, dynamic>) : null,
      );
}

class AiConversation {
  AiConversation({required this.id, required this.title, required this.lastMessageAt});
  final String id;
  final String title;
  final DateTime lastMessageAt;

  factory AiConversation.fromJson(Map<String, dynamic> j) => AiConversation(
        id: j['id'] as String? ?? '',
        title: j['title'] as String? ?? '',
        lastMessageAt: DateTime.tryParse(j['lastMessageAt'] as String? ?? '')?.toLocal() ?? DateTime.now(),
      );
}

class AiMessage {
  AiMessage({required this.role, required this.content, required this.createdAt});
  final int role; // 0 = user, 1 = assistant
  final String content;
  final DateTime createdAt;

  bool get isUser => role == 0;
  bool get isAssistant => role == 1;

  factory AiMessage.fromJson(Map<String, dynamic> j) => AiMessage(
        role: (j['role'] as num?)?.toInt() ?? 1,
        content: j['content'] as String? ?? '',
        createdAt: DateTime.tryParse(j['createdAt'] as String? ?? '')?.toLocal() ?? DateTime.now(),
      );
}

class AiCapability {
  AiCapability({required this.key, required this.title, required this.description, this.mobileRoute, required this.suggestions});
  final String key;
  final String title;
  final String description;
  final String? mobileRoute;
  final List<String> suggestions;

  factory AiCapability.fromJson(Map<String, dynamic> j) => AiCapability(
        key: j['key'] as String? ?? '',
        title: j['title'] as String? ?? '',
        description: j['description'] as String? ?? '',
        mobileRoute: j['mobileRoute'] as String?,
        suggestions: _strings(j['suggestions']),
      );
}

List<String> _strings(Object? v) => (v as List? ?? const []).map((e) => e.toString()).toList();

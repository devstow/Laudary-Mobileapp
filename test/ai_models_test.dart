import 'package:flutter_test/flutter_test.dart';
import 'package:mobileapp/models/ai.dart';

void main() {
  test('AiChatReply parses answer, links, pending action and filters web-only links', () {
    final r = AiChatReply.fromJson({
      'conversationId': 'c1',
      'answer': 'ORD-000197: In process',
      'mode': 0,
      'toolsUsed': ['track_order'],
      'navigationUrl': '/Portal/Details/x',
      'navigationLabel': 'Open order',
      'suggestions': ['Where is my order?'],
      'links': [
        {'label': 'ORD-000197', 'kind': 'order', 'id': 'x', 'webUrl': '/Portal/Details/x', 'mobileRoute': 'order/x'},
        {'label': 'Customers', 'kind': 'screen', 'id': null, 'webUrl': '/Customers', 'mobileRoute': null},
      ],
      'pendingAction': {'token': 't', 'tool': 'cancel_my_order', 'title': 'Cancel order', 'summary': 'Cancel ORD-000197?', 'destructive': true},
      'requiresConfirmation': true,
    });
    expect(r.conversationId, 'c1');
    expect(r.mode, 0);
    expect(r.links.length, 2);
    expect(r.mobileLinks.single.mobileRoute, 'order/x');
    expect(r.requiresConfirmation, isTrue);
    expect(r.pendingAction!.destructive, isTrue);
  });

  test('AiChatReply tolerates missing optional fields', () {
    final r = AiChatReply.fromJson({'conversationId': 'c', 'answer': 'hi'});
    expect(r.links, isEmpty);
    expect(r.pendingAction, isNull);
    expect(r.requiresConfirmation, isFalse);
  });

  test('AiState, conversations and messages', () {
    expect(AiState.fromJson({'enabled': true, 'suggestions': ['a']}).enabled, isTrue);
    expect(AiState.disabled.enabled, isFalse);
    final c = AiConversation.fromJson({'id': '1', 'title': 'T', 'lastMessageAt': '2026-10-08T10:00:00Z'});
    expect(c.title, 'T');
    final m = AiMessage.fromJson({'role': 0, 'content': 'q', 'mode': 0, 'createdAt': '2026-10-08T10:00:00Z'});
    expect(m.isUser, isTrue);
    expect(const AiPageContext(module: 'my_orders', recordType: 'order', recordId: 'x').toQuery()['recordId'], 'x');
  });
}

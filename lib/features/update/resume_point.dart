import 'dart:convert';

/// Where the user was when they tapped Update Now — ids only (no task data, no tokens), so the updated app can
/// reopen the same screen and load it FRESH from the server. Never replays an action.
class ResumePoint {
  const ResumePoint({required this.userId, required this.kind, required this.tab, this.id, this.label, required this.savedAt});

  final String userId;
  /// 'driverTask' (id = delivery task id), 'order' (id = order id) or 'tab' (just the bottom-nav tab).
  final String kind;
  final int tab;
  final String? id;
  final String? label;
  final DateTime savedAt;

  /// Restoring is only sensible shortly after the update; a stale point is ignored.
  static const maxAge = Duration(hours: 6);

  String toJson() => jsonEncode({'v': 1, 'userId': userId, 'kind': kind, 'tab': tab, 'id': id, 'label': label, 'savedAt': savedAt.toUtc().toIso8601String()});

  static ResumePoint? fromJson(String? s) {
    if (s == null || s.isEmpty) return null;
    try {
      final m = jsonDecode(s) as Map<String, dynamic>;
      if (m['v'] != 1) return null;
      return ResumePoint(
        userId: m['userId'] as String,
        kind: m['kind'] as String,
        tab: (m['tab'] as num?)?.toInt() ?? 0,
        id: m['id'] as String?,
        label: m['label'] as String?,
        savedAt: DateTime.parse(m['savedAt'] as String),
      );
    } catch (_) {
      return null;
    }
  }
}

/// What is on screen right now: the shells report their tab, detail screens register while open. Read when the user
/// starts an update.
class ScreenTracker {
  ScreenTracker._();

  static int tab = 0;
  static final List<({String kind, String id, String? label})> _stack = [];

  static void open(String kind, String id, {String? label}) => _stack.add((kind: kind, id: id, label: label));

  static void close(String kind, String id) {
    final i = _stack.lastIndexWhere((e) => e.kind == kind && e.id == id);
    if (i >= 0) _stack.removeAt(i);
  }

  static ResumePoint snapshot(String userId) {
    final top = _stack.isEmpty ? null : _stack.last;
    return ResumePoint(userId: userId, kind: top?.kind ?? 'tab', tab: tab, id: top?.id, label: top?.label, savedAt: DateTime.now());
  }

  static void reset() {
    tab = 0;
    _stack.clear();
  }
}

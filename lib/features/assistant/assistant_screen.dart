import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../l10n/l10n.dart';
import '../../models/ai.dart';
import '../../services/ai_service.dart';
import '../../services/api_exception.dart';
import '../../state/app_state.dart';
import '../../theme/app_theme.dart';
import '../../widgets/ui.dart';
import 'assistant_routes.dart';

/// Opens the assistant (optionally about the screen/record the user is on).
Future<void> openAssistant(BuildContext context, {AiPageContext? pageContext}) =>
    Navigator.of(context).push(MaterialPageRoute(builder: (_) => AssistantScreen(pageContext: pageContext)));

/// A header button that opens the assistant. Hidden unless the server says the assistant is enabled for this
/// user (global switch + the `ai.chat.use` permission) — checked once and cached for the session.
class AssistantButton extends StatefulWidget {
  const AssistantButton({super.key, this.pageContext, this.onDark = false, this.plain = false});
  final AiPageContext? pageContext;
  final bool onDark;

  /// Plain app-bar IconButton instead of the square header button.
  final bool plain;

  // Availability is cached per signed-in user (a different login re-checks it).
  static Future<bool>? _available;
  static String? _availableFor;

  @override
  State<AssistantButton> createState() => _AssistantButtonState();
}

class _AssistantButtonState extends State<AssistantButton> {
  late final Future<bool> _future = _resolve();

  Future<bool> _resolve() {
    final uid = context.read<AppState>().user?.id;
    if (AssistantButton._available == null || AssistantButton._availableFor != uid) {
      AssistantButton._availableFor = uid;
      AssistantButton._available = context.read<AiService>().state().then((s) => s.enabled);
    }
    return AssistantButton._available!;
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<bool>(
      future: _future,
      builder: (context, snap) {
        if (snap.data != true) return const SizedBox.shrink();
        void open() => openAssistant(context, pageContext: widget.pageContext);
        if (widget.plain) {
          return IconButton(icon: const Icon(Icons.auto_awesome_rounded), tooltip: context.t('AI Assistant'), onPressed: open);
        }
        return Padding(
          padding: const EdgeInsetsDirectional.only(end: 8),
          child: SquareIconButton(icon: Icons.auto_awesome_rounded, onTap: open, onDark: widget.onDark, tooltip: context.t('AI Assistant')),
        );
      },
    );
  }
}

// ---------------------------------------------------------------------------------------------------------------

enum _Kind { user, assistant, error, confirm }

class _Entry {
  _Entry(this.kind, this.text, {this.links = const [], this.action, this.retryMessage});
  final _Kind kind;
  final String text;
  final List<AiLink> links;
  final AiPendingAction? action;
  final String? retryMessage;
  bool resolved = false; // confirmation card answered
}

/// Full-screen chat with the shared AI assistant. All answers and actions come from the server (live, permission-
/// and tenant/branch-scoped data); this screen only renders them. Writes are never executed without an explicit
/// Confirm tap on the confirmation card.
class AssistantScreen extends StatefulWidget {
  const AssistantScreen({super.key, this.pageContext});
  final AiPageContext? pageContext;

  @override
  State<AssistantScreen> createState() => _AssistantScreenState();
}

class _AssistantScreenState extends State<AssistantScreen> {
  final _input = TextEditingController();
  final _scroll = ScrollController();
  final List<_Entry> _entries = [];
  List<String> _suggestions = const [];
  String? _conversationId;
  bool _busy = false;

  AiService get _ai => context.read<AiService>();

  @override
  void initState() {
    super.initState();
    _ai.state(context: widget.pageContext).then((s) {
      if (mounted) setState(() => _suggestions = s.suggestions);
    });
  }

  @override
  void dispose() {
    _input.dispose();
    _scroll.dispose();
    super.dispose();
  }

  void _scrollToEnd() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scroll.hasClients) _scroll.animateTo(_scroll.position.maxScrollExtent, duration: const Duration(milliseconds: 250), curve: Curves.easeOut);
    });
  }

  void _apply(AiChatReply r) {
    _conversationId = r.conversationId.isEmpty ? _conversationId : r.conversationId;
    _entries.add(_Entry(_Kind.assistant, r.answer, links: r.mobileLinks.where(AssistantRoutes.canOpen).toList()));
    if (r.pendingAction != null) _entries.add(_Entry(_Kind.confirm, r.pendingAction!.summary, action: r.pendingAction));
    if (r.suggestions.isNotEmpty) _suggestions = r.suggestions;
  }

  Future<void> _send(String text, {bool echo = true}) async {
    final msg = text.trim();
    if (msg.isEmpty || _busy) return;
    setState(() {
      _busy = true;
      if (echo) _entries.add(_Entry(_Kind.user, msg));
      _input.clear();
    });
    _scrollToEnd();
    try {
      final r = await _ai.chat(msg, conversationId: _conversationId, context: widget.pageContext);
      if (mounted) setState(() => _apply(r));
    } catch (e) {
      if (mounted) {
        setState(() => _entries.add(_Entry(_Kind.error, ApiException.from(e).message, retryMessage: msg)));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
      _scrollToEnd();
    }
  }

  Future<void> _confirm(_Entry card) async {
    if (_busy || card.resolved) return;
    setState(() {
      card.resolved = true;
      _busy = true;
    });
    try {
      final r = await _ai.confirm(card.action!.token, conversationId: _conversationId);
      if (mounted) setState(() => _apply(r));
    } catch (e) {
      if (mounted) {
        setState(() => _entries.add(_Entry(_Kind.error,
            context.t('Sorry, that action failed. Nothing was changed. Please try again or do it from the screen.'))));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
      _scrollToEnd();
    }
  }

  void _cancel(_Entry card) {
    if (card.resolved) return;
    setState(() {
      card.resolved = true;
      _entries.add(_Entry(_Kind.assistant, context.t('Okay — nothing was changed.')));
    });
    _scrollToEnd();
  }

  Future<void> _clear() async {
    final id = _conversationId;
    setState(() {
      _entries.clear();
      _conversationId = null;
    });
    if (id != null) {
      try {
        await _ai.deleteConversation(id);
      } catch (_) {/* best effort */}
    }
  }

  Future<void> _openLink(AiLink link) async {
    final ok = await AssistantRoutes.open(context, link);
    if (!ok && mounted) showToast(context, context.t("This screen isn't available in the app."), error: true);
  }

  Future<void> _showHistory() async {
    final picked = await showModalBottomSheet<AiConversation>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (_) => _HistorySheet(service: _ai),
    );
    if (picked == null || !mounted) return;
    setState(() {
      _busy = true;
      _entries.clear();
      _conversationId = picked.id;
    });
    try {
      final msgs = await _ai.messages(picked.id);
      if (!mounted) return;
      setState(() {
        for (final m in msgs) {
          if (m.isUser) _entries.add(_Entry(_Kind.user, m.content));
          if (m.isAssistant) _entries.add(_Entry(_Kind.assistant, m.content));
        }
      });
    } catch (e) {
      if (mounted) setState(() => _entries.add(_Entry(_Kind.error, ApiException.from(e).message)));
    } finally {
      if (mounted) setState(() => _busy = false);
      _scrollToEnd();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Row(mainAxisSize: MainAxisSize.min, children: [
          Container(
            width: 30,
            height: 30,
            decoration: BoxDecoration(gradient: AppColors.brandGradient, borderRadius: BorderRadius.circular(10)),
            child: const Icon(Icons.auto_awesome_rounded, color: Colors.white, size: 17),
          ),
          const SizedBox(width: 10),
          Flexible(child: Text(context.t('AI Assistant'), overflow: TextOverflow.ellipsis)),
        ]),
        actions: [
          IconButton(icon: const Icon(Icons.history_rounded), tooltip: context.t('History'), onPressed: _busy ? null : _showHistory),
          IconButton(icon: const Icon(Icons.delete_outline_rounded), tooltip: context.t('Clear chat'), onPressed: _busy ? null : _clear),
        ],
      ),
      body: SafeArea(
        top: false,
        child: Column(children: [
          Expanded(
            child: ListView(
              controller: _scroll,
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
              children: [
                _AssistantBubble(text: context.t('Hi! Ask me about your data — I answer from live information you are allowed to see.')),
                for (final e in _entries) _buildEntry(e),
                if (_busy) const _TypingBubble(),
              ],
            ),
          ),
          if (_suggestions.isNotEmpty && !_busy)
            SizedBox(
              height: 44,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                itemCount: _suggestions.length,
                separatorBuilder: (_, _) => const SizedBox(width: 8),
                itemBuilder: (_, i) => ActionChip(
                  label: Text(_suggestions[i], style: TextStyle(fontWeight: FontWeight.w600, fontSize: 12.5, color: AppColors.inkSoft)),
                  onPressed: () => _send(_suggestions[i]),
                ),
              ),
            ),
          _InputBar(controller: _input, busy: _busy, onSend: () => _send(_input.text)),
        ]),
      ),
    );
  }

  Widget _buildEntry(_Entry e) {
    switch (e.kind) {
      case _Kind.user:
        return _UserBubble(text: e.text);
      case _Kind.assistant:
        return _AssistantBubble(text: e.text, links: e.links, onLink: _openLink);
      case _Kind.error:
        return _AssistantBubble(
          text: e.text,
          isError: true,
          onRetry: e.retryMessage == null || _busy
              ? null
              : () {
                  setState(() => _entries.remove(e));
                  _send(e.retryMessage!, echo: false);
                },
        );
      case _Kind.confirm:
        return _ConfirmCard(
          action: e.action!,
          resolved: e.resolved,
          onConfirm: () => _confirm(e),
          onCancel: () => _cancel(e),
        );
    }
  }
}

// ---------------------------------------------------------------------------------------------------------------

class _UserBubble extends StatelessWidget {
  const _UserBubble({required this.text});
  final String text;
  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: AlignmentDirectional.centerEnd,
      child: Container(
        margin: const EdgeInsetsDirectional.only(top: 6, bottom: 6, start: 48),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: const BoxDecoration(
          gradient: AppColors.brandGradient,
          borderRadius: BorderRadiusDirectional.only(
            topStart: Radius.circular(18), topEnd: Radius.circular(18), bottomStart: Radius.circular(18), bottomEnd: Radius.circular(4)),
        ),
        child: Text(text, style: const TextStyle(color: Colors.white, fontSize: 14.5, height: 1.35)),
      ),
    );
  }
}

class _AssistantBubble extends StatelessWidget {
  const _AssistantBubble({required this.text, this.links = const [], this.onLink, this.isError = false, this.onRetry});
  final String text;
  final List<AiLink> links;
  final ValueChanged<AiLink>? onLink;
  final bool isError;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    final color = isError ? AppColors.danger : AppColors.ink;
    return Align(
      alignment: AlignmentDirectional.centerStart,
      child: Container(
        margin: const EdgeInsetsDirectional.only(top: 6, bottom: 6, end: 36),
        padding: const EdgeInsets.fromLTRB(14, 11, 14, 11),
        decoration: BoxDecoration(
          color: isError ? AppColors.danger.withValues(alpha: 0.08) : AppColors.surface,
          border: Border.all(color: isError ? AppColors.danger.withValues(alpha: 0.25) : AppColors.lineSoft),
          boxShadow: isError ? null : AppShadows.soft,
          borderRadius: const BorderRadiusDirectional.only(
            topStart: Radius.circular(18), topEnd: Radius.circular(18), bottomStart: Radius.circular(4), bottomEnd: Radius.circular(18)),
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          ..._formatted(text, color),
          if (links.isNotEmpty) ...[
            const SizedBox(height: 8),
            Wrap(spacing: 6, runSpacing: 6, children: [
              for (final l in links)
                InkWell(
                  borderRadius: BorderRadius.circular(AppRadius.chip),
                  onTap: onLink == null ? null : () => onLink!(l),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                    decoration: BoxDecoration(color: AppColors.primarySoft, borderRadius: BorderRadius.circular(AppRadius.chip)),
                    child: Row(mainAxisSize: MainAxisSize.min, children: [
                      Icon(l.kind == 'order' ? Icons.receipt_long_rounded : (l.kind == 'task' ? Icons.local_shipping_rounded : Icons.open_in_new_rounded),
                          size: 14, color: AppColors.primary),
                      const SizedBox(width: 5),
                      Text(l.label, style: const TextStyle(color: AppColors.primary, fontWeight: FontWeight.w700, fontSize: 12.5)),
                    ]),
                  ),
                ),
            ]),
          ],
          if (onRetry != null) ...[
            const SizedBox(height: 8),
            OutlinedButton.icon(
              onPressed: onRetry,
              icon: const Icon(Icons.refresh_rounded, size: 18),
              label: Text(context.t('Retry')),
              style: OutlinedButton.styleFrom(minimumSize: const Size(0, 40), padding: const EdgeInsets.symmetric(horizontal: 14)),
            ),
          ],
        ]),
      ),
    );
  }

  /// Bullet lines ("• …") become rows; **bold** spans are rendered bold. Everything else is plain text.
  static List<Widget> _formatted(String text, Color color) {
    final out = <Widget>[];
    for (final raw in text.split('\n')) {
      final line = raw.trimRight();
      if (line.trim().isEmpty) {
        out.add(const SizedBox(height: 6));
        continue;
      }
      final bullet = RegExp(r'^\s*[•\-–]\s+').firstMatch(line);
      final content = bullet == null ? line : line.substring(bullet.end);
      final rich = Text.rich(TextSpan(children: _spans(content)), style: TextStyle(color: color, fontSize: 14.5, height: 1.4));
      out.add(bullet == null
          ? Padding(padding: const EdgeInsets.symmetric(vertical: 1), child: rich)
          : Padding(
              padding: const EdgeInsets.symmetric(vertical: 2),
              child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                const Padding(
                  padding: EdgeInsetsDirectional.only(top: 7, end: 8),
                  child: CircleAvatar(radius: 2.6, backgroundColor: AppColors.primary),
                ),
                Expanded(child: rich),
              ]),
            ));
    }
    return out;
  }

  static List<InlineSpan> _spans(String s) {
    final spans = <InlineSpan>[];
    final re = RegExp(r'\*\*(.+?)\*\*');
    var i = 0;
    for (final m in re.allMatches(s)) {
      if (m.start > i) spans.add(TextSpan(text: s.substring(i, m.start)));
      spans.add(TextSpan(text: m.group(1), style: const TextStyle(fontWeight: FontWeight.w800)));
      i = m.end;
    }
    if (i < s.length) spans.add(TextSpan(text: s.substring(i)));
    return spans;
  }
}

class _ConfirmCard extends StatelessWidget {
  const _ConfirmCard({required this.action, required this.resolved, required this.onConfirm, required this.onCancel});
  final AiPendingAction action;
  final bool resolved;
  final VoidCallback onConfirm;
  final VoidCallback onCancel;

  @override
  Widget build(BuildContext context) {
    final c = action.destructive ? AppColors.danger : AppColors.primary;
    return AnimatedOpacity(
      duration: const Duration(milliseconds: 200),
      opacity: resolved ? 0.6 : 1,
      child: Container(
        margin: const EdgeInsetsDirectional.only(top: 6, bottom: 6, end: 24),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: c.withValues(alpha: 0.06),
          borderRadius: BorderRadius.circular(AppRadius.card),
          border: Border.all(color: c.withValues(alpha: 0.35)),
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Icon(action.destructive ? Icons.warning_amber_rounded : Icons.verified_user_rounded, color: c, size: 20),
            const SizedBox(width: 8),
            Expanded(child: Text(action.title, style: TextStyle(color: c, fontWeight: FontWeight.w800, fontSize: 15))),
          ]),
          const SizedBox(height: 8),
          Text(action.summary, style: TextStyle(color: AppColors.ink, fontSize: 14, height: 1.4)),
          const SizedBox(height: 12),
          Row(children: [
            Expanded(
              child: action.destructive
                  ? ElevatedButton(
                      onPressed: resolved ? null : onConfirm,
                      style: ElevatedButton.styleFrom(backgroundColor: AppColors.danger, minimumSize: const Size.fromHeight(46)),
                      child: Text(context.t('Confirm')),
                    )
                  : SizedBox(height: 46, child: PrimaryButton(label: context.t('Confirm'), onPressed: resolved ? null : onConfirm)),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: OutlinedButton(
                onPressed: resolved ? null : onCancel,
                style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(46)),
                child: Text(context.t('Cancel')),
              ),
            ),
          ]),
        ]),
      ),
    );
  }
}

class _TypingBubble extends StatefulWidget {
  const _TypingBubble();
  @override
  State<_TypingBubble> createState() => _TypingBubbleState();
}

class _TypingBubbleState extends State<_TypingBubble> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(vsync: this, duration: const Duration(milliseconds: 900))..repeat();
  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: AlignmentDirectional.centerStart,
      child: Semantics(
        label: context.t('Loading…'),
        child: Container(
          margin: const EdgeInsets.symmetric(vertical: 6),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          decoration: BoxDecoration(color: AppColors.surface, borderRadius: BorderRadius.circular(18), border: Border.all(color: AppColors.lineSoft)),
          child: AnimatedBuilder(
            animation: _c,
            builder: (_, _) => Row(mainAxisSize: MainAxisSize.min, children: [
              for (var i = 0; i < 3; i++)
                Container(
                  width: 7,
                  height: 7,
                  margin: const EdgeInsets.symmetric(horizontal: 2.5),
                  decoration: BoxDecoration(
                    color: AppColors.primary.withValues(alpha: 0.3 + 0.7 * (((_c.value * 3 - i) % 3) < 1 ? 1 : 0)),
                    shape: BoxShape.circle,
                  ),
                ),
            ]),
          ),
        ),
      ),
    );
  }
}

class _InputBar extends StatelessWidget {
  const _InputBar({required this.controller, required this.busy, required this.onSend});
  final TextEditingController controller;
  final bool busy;
  final VoidCallback onSend;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 10),
      decoration: BoxDecoration(color: AppColors.surface, border: Border(top: BorderSide(color: AppColors.lineSoft))),
      child: Row(children: [
        Expanded(
          child: TextField(
            controller: controller,
            minLines: 1,
            maxLines: 4,
            maxLength: 1000,
            textInputAction: TextInputAction.send,
            onSubmitted: (_) => onSend(),
            decoration: InputDecoration(hintText: context.t('Ask about your data…'), counterText: '', isDense: true),
          ),
        ),
        const SizedBox(width: 8),
        Material(
          color: Colors.transparent,
          child: InkWell(
            customBorder: const CircleBorder(),
            onTap: busy ? null : onSend,
            child: Ink(
              width: 48,
              height: 48,
              decoration: BoxDecoration(gradient: busy ? null : AppColors.brandGradient, color: busy ? AppColors.line : null, shape: BoxShape.circle),
              child: Icon(Icons.send_rounded, color: busy ? AppColors.faint : Colors.white, size: 21),
            ),
          ),
        ),
      ]),
    );
  }
}

class _HistorySheet extends StatelessWidget {
  const _HistorySheet({required this.service});
  final AiService service;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: SizedBox(
        height: MediaQuery.sizeOf(context).height * 0.6,
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
            child: Text(context.t('History'), style: Theme.of(context).textTheme.titleLarge),
          ),
          Expanded(
            child: FutureBuilder<List<AiConversation>>(
              future: service.conversations(),
              builder: (context, snap) {
                if (snap.connectionState == ConnectionState.waiting) return const LoadingView();
                if (snap.hasError) return ErrorView(ApiException.from(snap.error!).message);
                final items = snap.data ?? const [];
                if (items.isEmpty) return EmptyView(context.t('No conversations yet.'), icon: Icons.forum_outlined);
                return ListView.separated(
                  padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
                  itemCount: items.length,
                  separatorBuilder: (_, _) => const SizedBox(height: 6),
                  itemBuilder: (context, i) => ListTile(
                    leading: Icon(Icons.chat_bubble_outline_rounded, color: AppColors.primary),
                    title: Text(items[i].title, maxLines: 1, overflow: TextOverflow.ellipsis),
                    onTap: () => Navigator.of(context).pop(items[i]),
                  ),
                );
              },
            ),
          ),
        ]),
      ),
    );
  }
}

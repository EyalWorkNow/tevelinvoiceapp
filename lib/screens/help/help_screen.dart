// "עזרה": a small chat with the help assistant (owner request 2026-11-18).
// The assistant knows the app's screens and paths (server help corpus) and
// answers with deep-link chips; when it cannot help — or the member asks —
// "העבר לנציג" e-mails the conversation to help@tevel.space. Without the
// assistant (no key / provider down) the screen says so and keeps the
// hand-over to a person.

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:iconsax_flutter/iconsax_flutter.dart';

import '../../api/client.dart';
import '../../api/help_api.dart';
import '../../router.dart' show messengerKey;
import '../../state/session.dart';
import '../../ui/ds.dart';
import '../../ui/widgets/notch_notice.dart';
import '../../util/labels/help_he.dart';
import 'help_links.dart';

/// Replaceable in tests.
Future<HelpStatus> Function() loadHelpStatus = fetchHelpStatus;

/// Opens the help chat (from פרופיל → הגדרות → עזרה).
Future<void> openHelpScreen(BuildContext context) => Navigator.of(context).push(
  MaterialPageRoute<void>(
    settings: const RouteSettings(name: '/help'),
    builder: (_) => const HelpScreen(),
  ),
);

enum _Kind { user, assistant, notice, error }

class _Message {
  _Message(
    this.kind,
    this.text, {
    this.chips = const [],
    this.canHelp = true,
    this.retryQuestion,
  });

  final _Kind kind;
  final String text;
  final List<HelpChip> chips;
  final bool canHelp;

  /// error bubbles: the question "נסו שוב" re-sends.
  final String? retryQuestion;
}

class HelpScreen extends StatefulWidget {
  const HelpScreen({super.key});

  @override
  State<HelpScreen> createState() => _HelpScreenState();
}

class _HelpScreenState extends State<HelpScreen> {
  final _input = TextEditingController();
  final _scroll = ScrollController();
  final _messages = <_Message>[];
  String? _conversationId;
  String _supportEmail = helpEscalationEmail;
  bool _unavailable = false;
  bool _waiting = false;
  bool _escalating = false;

  @override
  void initState() {
    super.initState();
    unawaited(_loadStatus());
  }

  @override
  void dispose() {
    _input.dispose();
    _scroll.dispose();
    super.dispose();
  }

  Future<void> _loadStatus() async {
    try {
      final status = await loadHelpStatus();
      if (!mounted) return;
      setState(() {
        _unavailable = !status.available;
        _supportEmail = status.escalationEmail;
      });
    } on Object {
      // Offline / old server: the first question shows the real state.
    }
  }

  String? get _lastQuestion {
    for (final m in _messages.reversed) {
      if (m.kind == _Kind.user) return m.text;
    }
    return null;
  }

  void _scrollToEnd() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_scroll.hasClients) return;
      unawaited(
        _scroll.animateTo(
          _scroll.position.maxScrollExtent,
          duration: const Duration(milliseconds: 220),
          curve: Curves.easeOut,
        ),
      );
    });
  }

  Future<void> _ask(String raw, {bool echo = true}) async {
    final question = raw.trim();
    if (question.isEmpty || _waiting) return;
    setState(() {
      if (echo) _messages.add(_Message(_Kind.user, question));
      _waiting = true;
    });
    _input.clear();
    _scrollToEnd();
    try {
      final reply = await askHelp(question, conversationId: _conversationId);
      if (!mounted) return;
      setState(() {
        _conversationId = reply.conversationId.isEmpty
            ? _conversationId
            : reply.conversationId;
        _unavailable = false;
        _messages.add(
          _Message(
            _Kind.assistant,
            reply.answer,
            chips: reply.chips,
            canHelp: reply.canHelp,
          ),
        );
      });
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() {
        if (e.code == 'HELP_ASSISTANT_UNAVAILABLE') {
          _unavailable = true;
        } else {
          _messages.add(
            _Message(
              _Kind.error,
              switch (e.code) {
                'RATE_LIMITED' => HelpHe.rateLimited,
                'HELP_DAILY_LIMIT' => HelpHe.dailyLimit(_supportEmail),
                _ when e.isNetwork => HelpHe.offline,
                _ => HelpHe.failed,
              },
              retryQuestion: e.code == 'HELP_DAILY_LIMIT' ? null : question,
            ),
          );
        }
      });
    } on Object {
      if (!mounted) return;
      setState(
        () => _messages.add(
          _Message(_Kind.error, HelpHe.failed, retryQuestion: question),
        ),
      );
    } finally {
      if (mounted) setState(() => _waiting = false);
      _scrollToEnd();
    }
  }

  Future<void> _retry(_Message failed) async {
    setState(() => _messages.remove(failed));
    await _ask(failed.retryQuestion!, echo: false);
  }

  Future<void> _openChip(HelpChip chip) async {
    final opened = await openHelpLocation(context, chip.route);
    if (!opened && mounted) {
      messengerKey.currentState?.showNotchNotice(
        const SnackBar(content: Text(HelpHe.chipUnavailable)),
      );
    }
  }

  Future<void> _escalate({HelpEscalationReason? reason}) async {
    if (_escalating) return;
    final why =
        reason ??
        (_unavailable
            ? HelpEscalationReason.unavailable
            : HelpEscalationReason.userRequest);
    final hasConversation = _conversationId != null;
    // Without a logged conversation the question itself goes as the note.
    final draft = hasConversation ? '' : (_lastQuestion ?? _input.text.trim());
    final note = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      builder: (_) => _EscalateSheet(
        supportEmail: _supportEmail,
        contactEmail: session.account?.email,
        initialNote: draft,
      ),
    );
    if (note == null || !mounted) return;
    if (!hasConversation && note.trim().isEmpty) {
      _notice(HelpHe.escalateEmpty);
      return;
    }
    setState(() => _escalating = true);
    try {
      final ticket = await escalateHelp(
        conversationId: _conversationId,
        note: note,
        reason: why,
      );
      if (!mounted) return;
      setState(
        () => _messages.add(
          _Message(_Kind.notice, HelpHe.escalated(ticket.contactEmail)),
        ),
      );
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(
        () => _messages.add(
          _Message(
            _Kind.error,
            e.code == 'HELP_ESCALATION_LIMIT'
                ? HelpHe.escalateLimit(_supportEmail)
                : HelpHe.escalateFailed(_supportEmail),
          ),
        ),
      );
    } on Object {
      if (mounted) {
        setState(
          () => _messages.add(
            _Message(_Kind.error, HelpHe.escalateFailed(_supportEmail)),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _escalating = false);
      _scrollToEnd();
    }
  }

  void _notice(String text) =>
      messengerKey.currentState?.showNotchNotice(SnackBar(content: Text(text)));

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return Scaffold(
      appBar: AppBar(
        title: const Text(HelpHe.title),
        actions: [
          TextButton.icon(
            key: const Key('help-escalate'),
            onPressed: _escalating ? null : () => _escalate(),
            icon: const Icon(Iconsax.headphone, size: 18),
            label: const Text(HelpHe.escalate),
          ),
        ],
      ),
      body: SafeArea(
        child: Column(
          children: [
            if (_unavailable)
              _UnavailableBanner(
                supportEmail: _supportEmail,
                onEscalate: _escalating
                    ? null
                    : () => _escalate(reason: HelpEscalationReason.unavailable),
              ),
            Expanded(
              child: ListView(
                key: const Key('help-messages'),
                controller: _scroll,
                keyboardDismissBehavior:
                    ScrollViewKeyboardDismissBehavior.onDrag,
                padding: const EdgeInsets.fromLTRB(
                  Space.page,
                  Space.l,
                  Space.page,
                  Space.l,
                ),
                children: [
                  const _Bubble(kind: _Kind.assistant, text: HelpHe.greeting),
                  if (_messages.isEmpty) _Starters(onTap: _ask),
                  for (final m in _messages)
                    _Bubble(
                      kind: m.kind,
                      text: m.text,
                      chips: m.chips,
                      onChip: _openChip,
                      footer: switch (m) {
                        _Message(kind: _Kind.assistant, canHelp: false) =>
                          _InlineAction(
                            key: const Key('help-cannot-escalate'),
                            hint: HelpHe.cannotHelpHint,
                            label: HelpHe.escalate,
                            onTap: _escalating
                                ? null
                                : () => _escalate(
                                    reason: HelpEscalationReason.cannotHelp,
                                  ),
                          ),
                        _Message(kind: _Kind.error, retryQuestion: _?) =>
                          _InlineAction(
                            key: const Key('help-retry'),
                            label: HelpHe.retry,
                            onTap: _waiting ? null : () => _retry(m),
                          ),
                        _ => null,
                      },
                    ),
                  if (_waiting) const _Typing(),
                ],
              ),
            ),
            Container(
              decoration: BoxDecoration(
                color: p.surface,
                border: Border(top: BorderSide(color: p.line)),
              ),
              padding: const EdgeInsets.fromLTRB(
                Space.page,
                Space.s,
                Space.page,
                Space.s,
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: TextField(
                          key: const Key('help-input'),
                          controller: _input,
                          enabled: !_unavailable,
                          minLines: 1,
                          maxLines: 4,
                          maxLength: 1000,
                          textInputAction: TextInputAction.send,
                          onSubmitted: _ask,
                          decoration: const InputDecoration(
                            hintText: HelpHe.inputHint,
                            counterText: '',
                          ),
                        ),
                      ),
                      const SizedBox(width: Space.s),
                      IconButton.filled(
                        key: const Key('help-send'),
                        tooltip: HelpHe.send,
                        onPressed: _waiting || _unavailable
                            ? null
                            : () => _ask(_input.text),
                        icon: const Icon(Iconsax.send_1),
                      ),
                    ],
                  ),
                  const SizedBox(height: Space.xs),
                  Text(
                    HelpHe.privacyNotice,
                    key: const Key('help-privacy'),
                    style: AppText.secondary.copyWith(
                      color: p.muted,
                      fontSize: 11,
                    ),
                    textAlign: TextAlign.center,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Bubble extends StatelessWidget {
  const _Bubble({
    required this.kind,
    required this.text,
    this.chips = const [],
    this.onChip,
    this.footer,
  });

  final _Kind kind;
  final String text;
  final List<HelpChip> chips;
  final ValueChanged<HelpChip>? onChip;
  final Widget? footer;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final mine = kind == _Kind.user;
    final (Color bg, Color fg) = switch (kind) {
      _Kind.user => (DesignTokens.lavender, const Color(0xFF382844)),
      _Kind.assistant => (p.surface, p.ink),
      _Kind.notice => (p.ok.withValues(alpha: .12), p.ink),
      _Kind.error => (p.danger.withValues(alpha: .10), p.ink),
    };
    // RTL: the member's own messages on the start (right) side.
    return Align(
      alignment: mine
          ? AlignmentDirectional.centerStart
          : AlignmentDirectional.centerEnd,
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxWidth: MediaQuery.sizeOf(context).width * .82,
        ),
        child: Container(
          margin: const EdgeInsets.only(bottom: Space.s),
          padding: const EdgeInsets.symmetric(
            horizontal: Space.m,
            vertical: Space.s + 2,
          ),
          decoration: BoxDecoration(
            color: bg,
            border: mine ? null : Border.all(color: p.line),
            borderRadius: BorderRadiusDirectional.only(
              topStart: const Radius.circular(18),
              topEnd: const Radius.circular(18),
              bottomStart: Radius.circular(mine ? 4 : 18),
              bottomEnd: Radius.circular(mine ? 18 : 4),
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              SelectableText(text, style: AppText.body.copyWith(color: fg)),
              if (chips.isNotEmpty) ...[
                const SizedBox(height: Space.s),
                Wrap(
                  spacing: Space.s,
                  runSpacing: Space.xs,
                  children: [
                    for (final c in chips)
                      Tooltip(
                        message: c.path.isEmpty ? c.label : c.path,
                        child: ActionChip(
                          key: Key('help-chip-${c.id}'),
                          avatar: Icon(
                            Iconsax.arrow_left_2,
                            size: 16,
                            color: p.ink,
                          ),
                          label: Text(c.label),
                          onPressed: onChip == null ? null : () => onChip!(c),
                        ),
                      ),
                  ],
                ),
              ],
              ?footer,
            ],
          ),
        ),
      ),
    );
  }
}

class _InlineAction extends StatelessWidget {
  const _InlineAction({
    super.key,
    required this.label,
    required this.onTap,
    this.hint,
  });

  final String? hint;
  final String label;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(top: Space.s),
    child: Wrap(
      crossAxisAlignment: WrapCrossAlignment.center,
      spacing: Space.s,
      children: [
        if (hint != null)
          Text(
            hint!,
            style: AppText.secondary.copyWith(color: context.palette.muted),
          ),
        OutlinedButton(onPressed: onTap, child: Text(label)),
      ],
    ),
  );
}

class _Starters extends StatelessWidget {
  const _Starters({required this.onTap});

  final ValueChanged<String> onTap;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(top: Space.s, bottom: Space.m),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          HelpHe.startersTitle,
          style: AppText.secondary.copyWith(color: context.palette.muted),
        ),
        const SizedBox(height: Space.s),
        Wrap(
          spacing: Space.s,
          runSpacing: Space.s,
          children: [
            for (final (i, q) in HelpHe.starters.indexed)
              ActionChip(
                key: Key('help-starter-$i'),
                label: Text(q),
                onPressed: () => onTap(q),
              ),
          ],
        ),
      ],
    ),
  );
}

/// Three dots that breathe while the assistant answers.
class _Typing extends StatefulWidget {
  const _Typing();

  @override
  State<_Typing> createState() => _TypingState();
}

class _TypingState extends State<_Typing> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1100),
  );

  @override
  void initState() {
    super.initState();
    // Tests and reduce-motion: a still indicator (pumpAndSettle would wait forever).
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && !MediaQuery.disableAnimationsOf(context)) {
        unawaited(_c.repeat());
      }
    });
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return Align(
      alignment: AlignmentDirectional.centerEnd,
      child: Semantics(
        label: HelpHe.typing,
        child: Container(
          key: const Key('help-typing'),
          margin: const EdgeInsets.only(bottom: Space.s),
          padding: const EdgeInsets.symmetric(
            horizontal: Space.m,
            vertical: Space.m,
          ),
          decoration: BoxDecoration(
            color: p.surface,
            border: Border.all(color: p.line),
            borderRadius: BorderRadius.circular(18),
          ),
          child: AnimatedBuilder(
            animation: _c,
            builder: (context, _) => Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                for (var i = 0; i < 3; i++)
                  Container(
                    width: 7,
                    height: 7,
                    margin: const EdgeInsets.symmetric(horizontal: 2),
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: p.muted.withValues(
                        alpha:
                            .35 +
                            .65 *
                                (1 - ((_c.value * 3 - i) % 3).clamp(0, 1))
                                    .toDouble(),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _UnavailableBanner extends StatelessWidget {
  const _UnavailableBanner({required this.supportEmail, this.onEscalate});

  final String supportEmail;
  final VoidCallback? onEscalate;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return Container(
      key: const Key('help-unavailable'),
      width: double.infinity,
      margin: const EdgeInsets.fromLTRB(Space.page, Space.m, Space.page, 0),
      padding: const EdgeInsets.all(Space.card),
      decoration: BoxDecoration(
        color: p.warn.withValues(alpha: .12),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: p.warn.withValues(alpha: .4)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Iconsax.info_circle, color: p.warn, size: 20),
              const SizedBox(width: Space.s),
              const Text(HelpHe.unavailableTitle, style: AppText.button),
            ],
          ),
          const SizedBox(height: Space.xs),
          SelectableText(
            HelpHe.unavailableBody(supportEmail),
            style: AppText.secondary.copyWith(color: p.ink),
          ),
          const SizedBox(height: Space.s),
          FilledButton.icon(
            key: const Key('help-unavailable-escalate'),
            onPressed: onEscalate,
            icon: const Icon(Iconsax.headphone, size: 18),
            label: const Text(HelpHe.escalate),
          ),
        ],
      ),
    );
  }
}

class _EscalateSheet extends StatefulWidget {
  const _EscalateSheet({
    required this.supportEmail,
    required this.contactEmail,
    required this.initialNote,
  });

  final String supportEmail;
  final String? contactEmail;
  final String initialNote;

  @override
  State<_EscalateSheet> createState() => _EscalateSheetState();
}

class _EscalateSheetState extends State<_EscalateSheet> {
  late final _note = TextEditingController(text: widget.initialNote);

  @override
  void dispose() {
    _note.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Padding(
    padding: EdgeInsets.only(
      left: Space.page,
      right: Space.page,
      top: Space.l,
      bottom: MediaQuery.viewInsetsOf(context).bottom + Space.l,
    ),
    child: SafeArea(
      top: false,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Text(HelpHe.escalateTitle, style: AppText.headline),
          const SizedBox(height: Space.s),
          Text(
            HelpHe.escalateBody(widget.supportEmail, widget.contactEmail),
            style: AppText.body,
          ),
          const SizedBox(height: Space.m),
          TextField(
            key: const Key('help-escalate-note'),
            controller: _note,
            minLines: 2,
            maxLines: 5,
            maxLength: 2000,
            decoration: const InputDecoration(
              hintText: HelpHe.escalateNoteHint,
              counterText: '',
            ),
          ),
          const SizedBox(height: Space.m),
          FilledButton(
            key: const Key('help-escalate-send'),
            onPressed: () => Navigator.of(context).pop(_note.text),
            child: const Text(HelpHe.escalateSend),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text(HelpHe.cancel),
          ),
        ],
      ),
    ),
  );
}

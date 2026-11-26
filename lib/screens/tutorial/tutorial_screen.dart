// 2611 §1 "הדרכה בכניסה ראשונה": four full-screen cards (swipe), each with a
// gentle animation; "דלג" on top (first for VoiceOver), "הבא" / "בוא נתחיל" at
// the bottom. A member without money / calendar rights gets the short version
// (no collection card, no calendar card).

import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter/services.dart';
import 'package:iconsax_flutter/iconsax_flutter.dart';

import '../../state/business_context.dart';
import '../../state/caps.dart';
import '../../ui/ds.dart';
import '../../util/labels/tutorial_he.dart';
import '../calendar/calendar_screen.dart' show mayUseCalendar;
import '../calendar/google_calendar_guide.dart';

enum TutorialCard { document, debts, customers, calendar }

/// The cards this member gets (§1 edge case: an employee — no collection card
/// and no calendar card, by their permissions).
List<TutorialCard> tutorialCardsFor(Caps caps) => [
  TutorialCard.document,
  if (caps.can(Cap.moneyView)) TutorialCard.debts,
  TutorialCard.customers,
  if (mayUseCalendar(caps)) TutorialCard.calendar,
];

Future<void> openTutorial(BuildContext context) => Navigator.of(context).push(
  PageRouteBuilder<void>(
    settings: const RouteSettings(name: '/tutorial'),
    fullscreenDialog: true,
    transitionDuration: MediaQuery.disableAnimationsOf(context)
        ? Duration.zero
        : const Duration(milliseconds: 320),
    pageBuilder: (_, _, _) =>
        TutorialScreen(cards: tutorialCardsFor(businessContext.caps)),
    transitionsBuilder: (_, a, _, child) =>
        FadeTransition(opacity: a, child: child),
  ),
);

class TutorialScreen extends StatefulWidget {
  const TutorialScreen({super.key, required this.cards});

  final List<TutorialCard> cards;

  @override
  State<TutorialScreen> createState() => _TutorialScreenState();
}

class _TutorialScreenState extends State<TutorialScreen>
    with SingleTickerProviderStateMixin {
  final _pages = PageController();
  late final AnimationController _anim = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 2600),
  );
  int _page = 0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _play());
  }

  /// Each card plays its animation once when it comes into view; reduce
  /// motion shows the finished picture.
  void _play() {
    if (!mounted) return;
    if (MediaQuery.disableAnimationsOf(context)) {
      _anim.value = 1;
    } else {
      unawaited(_anim.forward(from: 0));
    }
  }

  @override
  void dispose() {
    _anim.dispose();
    _pages.dispose();
    super.dispose();
  }

  bool get _last => _page >= widget.cards.length - 1;

  void _close() => Navigator.of(context).maybePop();

  void _next() {
    HapticFeedback.selectionClick();
    if (_last) return _close();
    unawaited(
      _pages.nextPage(
        duration: MediaQuery.disableAnimationsOf(context)
            ? const Duration(milliseconds: 1)
            : const Duration(milliseconds: 320),
        curve: Curves.easeOutCubic,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final n = widget.cards.length;
    return Scaffold(
      key: const Key('tutorial'),
      body: SafeArea(
        child: Column(
          children: [
            // "דלג" first in the reading order (VoiceOver).
            Semantics(
              sortKey: const OrdinalSortKey(0),
              child: Padding(
                padding: const EdgeInsets.fromLTRB(
                  Space.s,
                  Space.s,
                  Space.s,
                  0,
                ),
                child: Row(
                  children: [
                    TextButton(
                      key: const Key('tutorial-skip'),
                      onPressed: _close,
                      child: const Text(TutorialHe.skip),
                    ),
                    const Spacer(),
                    Semantics(
                      label: TutorialHe.progress(_page + 1, n),
                      excludeSemantics: true,
                      child: Row(
                        children: [
                          for (var i = 0; i < n; i++)
                            AnimatedContainer(
                              duration: const Duration(milliseconds: 200),
                              margin: const EdgeInsets.symmetric(horizontal: 3),
                              width: i == _page ? 22 : 8,
                              height: 8,
                              decoration: BoxDecoration(
                                color: i == _page ? p.charcoal : p.line,
                                borderRadius: BorderRadius.circular(8),
                              ),
                            ),
                        ],
                      ),
                    ),
                    const SizedBox(width: Space.page),
                  ],
                ),
              ),
            ),
            Expanded(
              child: Semantics(
                sortKey: const OrdinalSortKey(1),
                child: PageView(
                  key: const Key('tutorial-pages'),
                  controller: _pages,
                  onPageChanged: (i) {
                    setState(() => _page = i);
                    _play();
                  },
                  children: [
                    for (final c in widget.cards)
                      _CardPage(card: c, anim: _anim),
                  ],
                ),
              ),
            ),
            Semantics(
              sortKey: const OrdinalSortKey(2),
              child: Padding(
                padding: const EdgeInsets.fromLTRB(
                  Space.page,
                  Space.s,
                  Space.page,
                  Space.l,
                ),
                child: PrimaryButton(
                  key: const Key('tutorial-next'),
                  label: _last ? TutorialHe.start : TutorialHe.next,
                  onPressed: _next,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _CardPage extends StatelessWidget {
  const _CardPage({required this.card, required this.anim});

  final TutorialCard card;
  final Animation<double> anim;

  (String, String) get _text => switch (card) {
    TutorialCard.document => (TutorialHe.docTitle, TutorialHe.docBody),
    TutorialCard.debts => (TutorialHe.debtsTitle, TutorialHe.debtsBody),
    TutorialCard.customers => (
      TutorialHe.customersTitle,
      TutorialHe.customersBody,
    ),
    TutorialCard.calendar => (
      TutorialHe.calendarTitle,
      TutorialHe.calendarBody,
    ),
  };

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final (title, body) = _text;
    return LayoutBuilder(
      builder: (context, box) => SingleChildScrollView(
        padding: const EdgeInsets.symmetric(horizontal: Space.page),
        child: ConstrainedBox(
          constraints: BoxConstraints(minHeight: box.maxHeight),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              // The picture is decoration: VoiceOver reads the text.
              ExcludeSemantics(
                child: SizedBox(
                  height: 240,
                  child: AnimatedBuilder(
                    animation: anim,
                    builder: (context, _) => switch (card) {
                      TutorialCard.document => _DocArt(t: anim.value),
                      TutorialCard.debts => _DebtsArt(t: anim.value),
                      TutorialCard.customers => _CustomerArt(t: anim.value),
                      TutorialCard.calendar => _CalendarArt(t: anim.value),
                    },
                  ),
                ),
              ),
              const SizedBox(height: Space.xl),
              Semantics(
                header: true,
                child: Text(
                  title,
                  key: Key('tutorial-title-${card.name}'),
                  style: AppText.displayTitle,
                  textAlign: TextAlign.center,
                ),
              ),
              const SizedBox(height: Space.m),
              Text(
                body,
                style: AppText.body.copyWith(color: p.muted),
                textAlign: TextAlign.center,
              ),
              if (card == TutorialCard.calendar &&
                  Theme.of(context).platform == TargetPlatform.iOS) ...[
                const SizedBox(height: Space.m),
                TextButton.icon(
                  key: const Key('tutorial-google'),
                  onPressed: () => unawaited(openGoogleCalendarGuide(context)),
                  icon: const Icon(Iconsax.calendar_add, size: 20),
                  label: const Text(TutorialHe.calendarGoogle),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

/// 0..1 → how far the [i]-th of [n] staggered items has appeared.
double _stagger(double t, int i, int n) =>
    ((t * (n + 1)) - i).clamp(0.0, 1.0).toDouble();

/// "+ → לקוח → סכום → נשלח": the steps light up one after the other.
class _DocArt extends StatelessWidget {
  const _DocArt({required this.t});

  final double t;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    const steps = TutorialHe.docSteps;
    final active = (t * steps.length).floor().clamp(0, steps.length - 1);
    final colors = [
      DesignTokens.lavender,
      DesignTokens.yellow,
      DesignTokens.coral,
      DesignTokens.green,
    ];
    return Center(
      child: Wrap(
        alignment: WrapAlignment.center,
        crossAxisAlignment: WrapCrossAlignment.center,
        spacing: Space.xs,
        runSpacing: Space.s,
        children: [
          for (var i = 0; i < steps.length; i++) ...[
            AnimatedScale(
              scale: i == active ? 1.12 : 1,
              duration: const Duration(milliseconds: 250),
              child: Container(
                width: 70,
                height: 70,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: i <= active ? colors[i] : p.line,
                ),
                child: i == steps.length - 1 && i <= active
                    ? const Icon(Icons.check_rounded, size: 30)
                    : Text(
                        steps[i],
                        style: AppText.headline.copyWith(
                          color: const Color(0xFF302139),
                          fontWeight: FontWeight.w700,
                        ),
                      ),
              ),
            ),
            if (i < steps.length - 1)
              Icon(Icons.arrow_forward_rounded, size: 18, color: p.muted),
          ],
        ],
      ),
    );
  }
}

/// The "חייבים לך" card, then a WhatsApp bubble slides in.
class _DebtsArt extends StatelessWidget {
  const _DebtsArt({required this.t});

  final double t;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final bubble = Curves.easeOutBack.transform(_stagger(t, 1, 2));
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Container(
          width: 260,
          padding: const EdgeInsets.all(Space.m),
          decoration: BoxDecoration(
            color: p.charcoal,
            borderRadius: BorderRadius.circular(Radii.card),
          ),
          child: Row(
            children: [
              Icon(Iconsax.wallet_money, color: p.onCharcoal),
              const SizedBox(width: Space.s),
              Expanded(
                child: Text(
                  TutorialHe.debtsCard,
                  style: AppText.headline.copyWith(color: p.onCharcoal),
                ),
              ),
              Icon(Icons.chevron_right, color: p.onCharcoalMuted),
            ],
          ),
        ),
        const SizedBox(height: Space.l),
        Opacity(
          opacity: bubble.clamp(0.0, 1.0),
          child: Transform.translate(
            offset: Offset(0, 24 * (1 - bubble)),
            child: Container(
              width: 250,
              padding: const EdgeInsets.all(Space.m),
              decoration: BoxDecoration(
                color: p.whatsapp.withValues(alpha: .18),
                borderRadius: BorderRadius.circular(18),
              ),
              child: Row(
                children: [
                  Icon(Iconsax.message, color: p.whatsapp),
                  const SizedBox(width: Space.s),
                  Expanded(
                    child: Text(
                      TutorialHe.debtsBubble,
                      style: AppText.secondary,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }
}

/// A customer card whose quick actions pop in one by one.
class _CustomerArt extends StatelessWidget {
  const _CustomerArt({required this.t});

  final double t;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    const orbs = [
      (Iconsax.receipt_add, DesignTokens.coral),
      (Iconsax.money_recive, DesignTokens.lavender),
      (Iconsax.calendar_add, DesignTokens.green),
      (Iconsax.notification, DesignTokens.yellow),
    ];
    return Center(
      child: Container(
        width: 280,
        padding: const EdgeInsets.all(Space.l),
        decoration: BoxDecoration(
          color: p.surface,
          borderRadius: BorderRadius.circular(Radii.card),
          border: Border.all(color: p.line),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                CircleAvatar(
                  radius: 22,
                  backgroundColor: p.line,
                  child: Icon(Iconsax.user, color: p.ink),
                ),
                const SizedBox(width: Space.m),
                Text(TutorialHe.customersSample, style: AppText.headline),
              ],
            ),
            const SizedBox(height: Space.l),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                for (var i = 0; i < orbs.length; i++)
                  Transform.scale(
                    scale: Curves.easeOutBack
                        .transform(_stagger(t, i, orbs.length))
                        .clamp(0.0, 1.2),
                    child: CircleAvatar(
                      radius: 26,
                      backgroundColor: orbs[i].$2,
                      child: Icon(
                        orbs[i].$1,
                        color: const Color(0xFF302139),
                        size: 24,
                      ),
                    ),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// A week strip with a booked day and a bell that rings.
class _CalendarArt extends StatelessWidget {
  const _CalendarArt({required this.t});

  final double t;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final booked = t > .35;
    final ring = booked ? math.sin(t * math.pi * 10) * .25 * (1 - t) : 0.0;
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Transform.rotate(
          angle: ring,
          child: Icon(
            Iconsax.notification_bing,
            size: 40,
            color: booked ? p.warn : p.muted,
          ),
        ),
        const SizedBox(height: Space.m),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            for (var d = 0; d < 7; d++)
              AnimatedContainer(
                duration: const Duration(milliseconds: 300),
                margin: const EdgeInsets.symmetric(horizontal: 3),
                width: 36,
                height: 48,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: booked && d == 3 ? p.charcoal : p.surface,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: p.line),
                ),
                child: Text(
                  '${d + 1}',
                  style: AppText.body.copyWith(
                    color: booked && d == 3 ? p.onCharcoal : p.ink,
                  ),
                ),
              ),
          ],
        ),
        const SizedBox(height: Space.m),
        AnimatedOpacity(
          opacity: booked ? 1 : 0,
          duration: const Duration(milliseconds: 300),
          child: Text(
            TutorialHe.calendarBooked,
            style: AppText.secondary.copyWith(color: p.muted),
          ),
        ),
      ],
    );
  }
}

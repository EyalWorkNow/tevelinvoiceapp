// "קביעת פגישה" from the customer page (calendar v2, owner / partner):
//   · הצעת מועדים — pick up to 3 of the next free slots; the customer gets a
//     personal link that offers only those (POST /calendar/invites).
//   · שליחת קישור ליומן — the same personal link, every free slot.
//   · קביעה בשמו — the owner books a slot for the customer (CONFIRMED).
// The invite text goes to WhatsApp when the customer has a phone, else to the
// share sheet. A switched-off calendar explains itself and can be turned on.

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:iconsax_flutter/iconsax_flutter.dart';

import '../../api/client.dart' show ApiException;
import '../../state/business_context.dart';
import '../../ui/ds.dart';
import '../../ui/widgets/notch_notice.dart';
import '../../util/allowed_urls.dart';
import '../../util/labels/calendar_he.dart';
import '../../util/labels/common_he.dart';
import '../../util/phone.dart';
import '../document/dialogs.dart' show toast;
import '../document/sheets/s6_share.dart' show textSharer;
import 'calendar_api.dart';

enum CustomerBookingMode { suggest, link, book }

const maxSuggestedSlots = 3;

Future<void> showCustomerBookingSheet(
  BuildContext context, {
  required String customerId,
  required String name,
  String? phone,
}) => showAppSheet<void>(
  context,
  builder: (_) =>
      CustomerBookingSheet(customerId: customerId, name: name, phone: phone),
);

/// "ראשון 23.11 · 10:00" ("היום" / "מחר" for those days).
String slotLabel(FreeSlot s, {DateTime? now}) {
  final d = DateTime.tryParse(s.date);
  if (d == null) return s.time;
  final n = now ?? DateTime.now();
  final today = DateTime(n.year, n.month, n.day);
  final day = DateTime(d.year, d.month, d.day);
  final name = day == today
      ? CalendarHe.today
      : day == today.add(const Duration(days: 1))
      ? CalendarHe.tomorrow
      : CalendarHe.days[day.weekday % 7];
  final dm =
      '${day.day.toString().padLeft(2, '0')}.${day.month.toString().padLeft(2, '0')}';
  return '$name $dm · ${s.time}';
}

class CustomerBookingSheet extends StatefulWidget {
  const CustomerBookingSheet({
    super.key,
    required this.customerId,
    required this.name,
    this.phone,
  });

  final String customerId;
  final String name;
  final String? phone;

  @override
  State<CustomerBookingSheet> createState() => _CustomerBookingSheetState();
}

class _CustomerBookingSheetState extends State<CustomerBookingSheet> {
  CustomerBookingMode _mode = CustomerBookingMode.suggest;
  FreeSlots? _slots;
  Object? _error;
  String? _notice;
  final List<String> _selected = [];
  String? _pick;
  bool _sending = false;

  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  Future<void> _load({String? notice}) async {
    setState(() {
      _error = null;
      _notice = notice;
    });
    try {
      final s = await fetchFreeSlots();
      if (!mounted) return;
      final starts = {for (final x in s.slots) x.start};
      setState(() {
        _slots = s;
        _selected.removeWhere((x) => !starts.contains(x));
        if (!starts.contains(_pick)) _pick = null;
      });
    } on Object catch (e) {
      if (mounted) setState(() => _error = e);
    }
  }

  Future<void> _enable() async {
    try {
      await saveCalendarSettings({'enabled': true});
      if (mounted) await _load();
    } on Object catch (e) {
      if (mounted) showErrorSnack(context, e);
    }
  }

  void _toggle(String start) {
    setState(() {
      if (_selected.contains(start)) {
        _selected.remove(start);
      } else if (_selected.length < maxSuggestedSlots) {
        _selected.add(start);
      } else {
        toast(context, CalendarHe.maxThree);
      }
    });
  }

  /// A slot no longer free (or the calendar went off): show what is free now.
  bool _recover(ApiException e) {
    if (e.code == 'SLOT_TAKEN' || e.code == 'VALIDATION') {
      unawaited(_load(notice: CalendarHe.slotTaken));
      return true;
    }
    if (e.code == 'CALENDAR_DISABLED') {
      unawaited(_load());
      return true;
    }
    return false;
  }

  Future<void> _sendInvite() async {
    if (_sending) return;
    final suggest = _mode == CustomerBookingMode.suggest;
    if (suggest && _selected.isEmpty) {
      toast(context, CalendarHe.pickSlot);
      return;
    }
    setState(() => _sending = true);
    try {
      final invite = await createCalendarInvite(
        widget.customerId,
        slots: suggest ? [..._selected] : const [],
      );
      if (!mounted) return;
      Navigator.of(context).pop();
      final wa = waPhone(widget.phone);
      if (wa != null) {
        await launchAllowed(whatsAppUri(phone: wa, text: invite.whatsappText));
      } else {
        await textSharer(invite.whatsappText);
      }
    } on ApiException catch (e) {
      if (mounted && !_recover(e)) showErrorSnack(context, e);
    } on Object catch (e) {
      if (mounted) showErrorSnack(context, e);
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  Future<void> _book() async {
    if (_sending) return;
    final start = _pick;
    final slot = _slots?.slots.where((s) => s.start == start).firstOrNull;
    if (start == null || slot == null) {
      toast(context, CalendarHe.pickSlot);
      return;
    }
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: Text(CalendarHe.bookConfirmTitle(widget.name)),
        content: Text('${slotLabel(slot)}\n\n${CalendarHe.bookConfirmEmail}'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(c, false),
            child: const Text(CommonHe.cancel),
          ),
          TextButton(
            key: const Key('customer-book-confirm'),
            onPressed: () => Navigator.pop(c, true),
            child: const Text(CalendarHe.bookConfirm),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    setState(() => _sending = true);
    try {
      await bookForCustomer(widget.customerId, start);
      if (!mounted) return;
      final messenger = ScaffoldMessenger.maybeOf(context);
      Navigator.of(context).pop();
      messenger
        ?..hideCurrentNotchNotice()
        ..showNotchNotice(
          const SnackBar(content: Text(CalendarHe.booked)),
          motion: NoticeMotion.calendar,
        );
    } on ApiException catch (e) {
      if (mounted && !_recover(e)) showErrorSnack(context, e);
    } on Object catch (e) {
      if (mounted) showErrorSnack(context, e);
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final slots = _slots;
    final children = <Widget>[
      SheetTitle(CalendarHe.bookFor, subtitle: widget.name),
    ];
    if (slots == null) {
      children.add(
        _error != null
            ? ErrorView(error: _error!, onRetry: () => unawaited(_load()))
            : const Padding(
                padding: EdgeInsets.all(Space.xl),
                child: Center(child: CircularProgressIndicator.adaptive()),
              ),
      );
    } else if (!slots.enabled) {
      children.addAll([
        AppCard(
          key: const Key('customer-book-disabled'),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(Iconsax.info_circle, color: p.warn),
                  const SizedBox(width: Space.s),
                  const Expanded(
                    child: Text(
                      CalendarHe.disabledTitle,
                      style: AppText.headline,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: Space.xs),
              Text(
                CalendarHe.disabledBody,
                style: AppText.secondary.copyWith(color: p.muted),
              ),
            ],
          ),
        ),
        const SizedBox(height: Space.m),
        PrimaryButton(
          key: const Key('customer-book-primary'),
          label: CalendarHe.enable,
          offline: businessContext.offline,
          onPressed: () => unawaited(_enable()),
        ),
      ]);
    } else {
      children.addAll([
        ChipRow<CustomerBookingMode>(
          key: const Key('customer-book-mode'),
          padding: EdgeInsets.zero,
          options: const [
            ChipOption(CustomerBookingMode.suggest, CalendarHe.modeSuggest),
            ChipOption(CustomerBookingMode.link, CalendarHe.modeLink),
            ChipOption(CustomerBookingMode.book, CalendarHe.modeBook),
          ],
          selected: _mode,
          onSelected: (m) => setState(() => _mode = m),
        ),
        const SizedBox(height: Space.m),
        Text(switch (_mode) {
          CustomerBookingMode.suggest => CalendarHe.suggestHint,
          CustomerBookingMode.link => CalendarHe.linkHint,
          CustomerBookingMode.book => CalendarHe.bookHint,
        }, style: AppText.secondary.copyWith(color: p.muted)),
        if (_notice != null)
          Padding(
            padding: const EdgeInsets.only(top: Space.s),
            child: Text(
              _notice!,
              key: const Key('customer-book-notice'),
              style: AppText.secondary.copyWith(color: p.warn),
            ),
          ),
        const SizedBox(height: Space.s),
        if (_mode != CustomerBookingMode.link)
          if (slots.slots.isEmpty)
            Text(
              CalendarHe.noFreeSlots,
              key: const Key('customer-book-empty'),
              style: AppText.body.copyWith(color: p.muted),
            )
          else
            Wrap(
              spacing: Space.s,
              runSpacing: Space.s,
              children: [
                for (final (i, s) in slots.slots.indexed)
                  _mode == CustomerBookingMode.suggest
                      ? FilterChip(
                          key: Key('customer-slot-$i'),
                          label: Text(slotLabel(s)),
                          selected: _selected.contains(s.start),
                          onSelected: (_) => _toggle(s.start),
                        )
                      : ChoiceChip(
                          key: Key('customer-slot-$i'),
                          label: Text(slotLabel(s)),
                          selected: _pick == s.start,
                          onSelected: (_) => setState(() => _pick = s.start),
                        ),
              ],
            ),
        const SizedBox(height: Space.l),
        if (_mode == CustomerBookingMode.book)
          PrimaryButton(
            key: const Key('customer-book-primary'),
            label: CalendarHe.bookConfirm,
            icon: Iconsax.calendar_tick,
            loadingText: _sending ? CalendarHe.bookConfirm : null,
            offline: businessContext.offline,
            onPressed: () => unawaited(_book()),
          )
        else
          PrimaryButton(
            key: const Key('customer-book-primary'),
            label: CalendarHe.sendInvite,
            icon: waPhone(widget.phone) != null
                ? Iconsax.message
                : Iconsax.share,
            loadingText: _sending ? CalendarHe.sendInvite : null,
            offline: businessContext.offline,
            onPressed: () => unawaited(_sendInvite()),
          ),
      ]);
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: children,
    );
  }
}

// "קביעת פגישה" from the customer page (calendar v2, owner / partner):
//   · הצעת מועדים — pick up to 3 free times (also on different days); the
//     customer gets a personal link that offers only those (POST /calendar/invites).
//   · קביעה בשמו — the owner books one time for the customer (CONFIRMED), with
//     an optional note; without an e-mail the details can go out on WhatsApp.
//   · קישור ליומן — the same personal link, every free slot (7 days).
// A day strip (GET /calendar/free-slots → days[]) picks the day; that day's
// times (?date=) sit below in an even 4-per-row grid. A switched-off calendar
// shows its default hours, "שינוי שעות" and "הפעלה".

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
import 'calendar_layout.dart' show monthOf;
import 'new_booking_sheet.dart' show CalendarMonthPicker;
import '../../util/labels/person_page_he.dart';
import '../../util/phone.dart';
import '../document/dialogs.dart' show toast;
import '../document/sheets/s6_share.dart' show textSharer;
import 'calendar_api.dart';
import 'calendar_settings_screen.dart' show openCalendarSettings;

enum CustomerBookingMode { suggest, book, link }

const maxSuggestedSlots = 3;

Future<void> showCustomerBookingSheet(
  BuildContext context, {
  required String customerId,
  required String name,
  String? phone,
  String? email,
}) => showAppSheet<void>(
  context,
  builder: (_) => CustomerBookingSheet(
    customerId: customerId,
    name: name,
    phone: phone,
    email: email,
  ),
);

String _dm(DateTime d) =>
    '${d.day.toString().padLeft(2, '0')}.${d.month.toString().padLeft(2, '0')}';

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
  return '$name ${_dm(day)} · ${s.time}';
}

/// The strip's days: every day from the first bookable one to the last;
/// days the server did not list (closed, full, vacation) have 0 free times
/// and are shown, not selectable.
List<FreeDay> dayStrip(List<FreeDay> days) {
  final parsed = [
    for (final d in days)
      if (DateTime.tryParse(d.date) case final DateTime at) (at, d.count),
  ]..sort((a, b) => a.$1.compareTo(b.$1));
  if (parsed.isEmpty) return const [];
  final first = parsed.first.$1;
  final last = parsed.last.$1;
  final counts = {for (final p in parsed) ymd(p.$1): p.$2};
  return [
    for (
      var d = DateTime(first.year, first.month, first.day);
      !d.isAfter(last);
      d = DateTime(d.year, d.month, d.day + 1)
    )
      FreeDay(ymd(d), counts[ymd(d)] ?? 0),
  ];
}

/// "א׳–ה׳ 09:00–17:00 · ו׳ 09:00–13:00" (consecutive days with the same
/// hours together); empty when no day is open.
String hoursSummary(List<DayHours> week) {
  final byDay = {for (final d in week) d.day: d};
  String hours(DayHours d) =>
      d.ranges.map((r) => '${r.start}–${r.end}').join(', ');
  final parts = <String>[];
  var day = 0;
  while (day < 7) {
    final d = byDay[day];
    if (d == null || !d.open) {
      day++;
      continue;
    }
    var end = day;
    while (end + 1 < 7 &&
        byDay[end + 1] != null &&
        byDay[end + 1]!.open &&
        hours(byDay[end + 1]!) == hours(d)) {
      end++;
    }
    final w = PersonPageHe.weekdayShort;
    parts.add(
      '${end == day ? w[day] : '${w[day]}–${w[end]}'} ${ltrIsolate(hours(d))}',
    );
    day = end + 1;
  }
  return parts.join(' · ');
}

class CustomerBookingSheet extends StatefulWidget {
  const CustomerBookingSheet({
    super.key,
    required this.customerId,
    required this.name,
    this.phone,
    this.email,
  });

  final String customerId;
  final String name;
  final String? phone;
  final String? email;

  @override
  State<CustomerBookingSheet> createState() => _CustomerBookingSheetState();
}

class _CustomerBookingSheetState extends State<CustomerBookingSheet> {
  CustomerBookingMode _mode = CustomerBookingMode.suggest;
  bool? _enabled;
  List<FreeDay> _strip = const [];
  String? _day;
  DateTime? _month;
  final Map<String, List<FreeSlot>> _byDay = {};
  bool _dayLoading = false;
  Object? _error;
  String? _notice;
  final List<FreeSlot> _picks = [];
  FreeSlot? _pick;
  CalendarSettings? _settings;
  bool _sending = false;
  final _notes = TextEditingController();

  bool get _hasEmail => (widget.email ?? '').trim().isNotEmpty;

  /// No phone and no e-mail: an invite or link cannot reach them, so only
  /// "קביעה בשמו" is offered.
  bool get _noContact => !_hasEmail && (widget.phone ?? '').trim().isEmpty;

  @override
  void initState() {
    super.initState();
    if (_noContact) _mode = CustomerBookingMode.book;
    unawaited(_load());
  }

  @override
  void dispose() {
    _notes.dispose();
    super.dispose();
  }

  Future<void> _load({String? notice}) async {
    setState(() {
      _error = null;
      _notice = notice;
    });
    try {
      final s = await fetchFreeSlots();
      if (!mounted) return;
      if (!s.enabled) {
        setState(() => _enabled = false);
        try {
          final settings = await fetchCalendarSettings();
          if (mounted) setState(() => _settings = settings);
        } on Object {
          // The hours line is a hint; the switch below still works.
        }
        return;
      }
      // An older server sends no days[]: derive them from the slots.
      final derived = s.days.isEmpty;
      final days = derived
          ? [
              for (final e in _groupByDay(s.slots).entries)
                FreeDay(e.key, e.value.length),
            ]
          : s.days;
      final strip = dayStrip(days);
      final keep =
          _day != null && strip.any((d) => d.date == _day && d.count > 0);
      final first = strip.where((d) => d.count > 0).firstOrNull?.date;
      setState(() {
        _enabled = true;
        _strip = strip;
        _byDay.clear();
        if (derived) _byDay.addAll(_groupByDay(s.slots));
        _day = keep ? _day : first;
        final d = _day;
        _month = d == null ? null : monthOf(DateTime.parse(d));
      });
      final day = _day;
      if (!derived && day != null) await _loadDay(day);
    } on Object catch (e) {
      if (mounted) setState(() => _error = e);
    }
  }

  static Map<String, List<FreeSlot>> _groupByDay(List<FreeSlot> slots) {
    final out = <String, List<FreeSlot>>{};
    for (final s in slots) {
      (out[s.date] ??= []).add(s);
    }
    return out;
  }

  Future<void> _loadDay(String date, {bool force = false}) async {
    if (!force && _byDay.containsKey(date)) return;
    setState(() => _dayLoading = true);
    try {
      final s = await fetchFreeSlots(date: date);
      if (!mounted) return;
      if (!s.enabled) {
        unawaited(_load());
        return;
      }
      setState(() {
        _byDay[date] = s.slots.where((x) => x.date == date).toList();
        // The day's count follows what is free now.
        _strip = [
          for (final d in _strip)
            d.date == date ? FreeDay(date, _byDay[date]!.length) : d,
        ];
        final starts = {for (final x in _byDay[date]!) x.start};
        _picks.removeWhere((p) => p.date == date && !starts.contains(p.start));
        if (_pick?.date == date && !starts.contains(_pick!.start)) _pick = null;
      });
    } on Object catch (e) {
      if (mounted) showErrorSnack(context, e);
    } finally {
      if (mounted) setState(() => _dayLoading = false);
    }
  }

  void _selectDay(FreeDay d) {
    if (d.count == 0 || d.date == _day) return;
    setState(() => _day = d.date);
    unawaited(_loadDay(d.date));
  }

  Future<void> _enable() async {
    try {
      await saveCalendarSettings({'enabled': true});
      if (mounted) await _load();
    } on Object catch (e) {
      if (mounted) showErrorSnack(context, e);
    }
  }

  Future<void> _openHours() async {
    await openCalendarSettings(context);
    if (mounted) await _load();
  }

  void _toggle(FreeSlot s) {
    setState(() {
      final i = _picks.indexWhere((p) => p.start == s.start);
      if (i >= 0) {
        _picks.removeAt(i);
      } else if (_picks.length < maxSuggestedSlots) {
        _picks.add(s);
      } else {
        toast(context, CalendarHe.maxThree);
      }
    });
  }

  /// A time no longer free (or the calendar went off): reload that day.
  bool _recover(ApiException e) {
    if (e.code == 'SLOT_TAKEN' || e.code == 'VALIDATION') {
      setState(() => _notice = CalendarHe.slotTaken);
      final day = _day;
      if (day != null) unawaited(_loadDay(day, force: true));
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
    if (suggest && _picks.isEmpty) {
      toast(context, CalendarHe.pickSlot);
      return;
    }
    setState(() => _sending = true);
    try {
      final invite = await createCalendarInvite(
        widget.customerId,
        slots: suggest ? [for (final p in _picks) p.start] : const [],
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

  String get _confirmLine => _hasEmail
      ? CalendarHe.confirmByEmail(widget.name)
      : waPhone(widget.phone) != null
      ? CalendarHe.confirmByPhone
      : CalendarHe.confirmNoContact;

  Future<void> _book() async {
    if (_sending) return;
    final slot = _pick;
    if (slot == null) {
      toast(context, CalendarHe.pickSlot);
      return;
    }
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: Text(CalendarHe.bookConfirmTitle(widget.name)),
        content: Text('${slotLabel(slot)}\n\n$_confirmLine'),
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
      await bookForCustomer(widget.customerId, slot.start, notes: _notes.text);
      if (!mounted) return;
      final wa = waPhone(widget.phone);
      // No e-mail confirmation reaches them: offer the details on WhatsApp.
      if (!_hasEmail && wa != null) {
        final send = await showDialog<bool>(
          context: context,
          builder: (c) => AlertDialog(
            title: const Text(CalendarHe.offerWhatsappTitle),
            content: Text(
              CalendarHe.offerWhatsappBody(widget.name, slotLabel(slot)),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(c, false),
                child: const Text(CalendarHe.notNow),
              ),
              TextButton(
                key: const Key('customer-book-whatsapp'),
                onPressed: () => Navigator.pop(c, true),
                child: const Text(CalendarHe.sendWhatsapp),
              ),
            ],
          ),
        );
        if (!mounted) return;
        if (send == true) {
          unawaited(
            launchAllowed(
              whatsAppUri(
                phone: wa,
                text: CalendarHe.whatsappDetails(
                  widget.name,
                  slotLabel(slot),
                  businessContext.displayName,
                ),
              ),
            ),
          );
        }
      }
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
    final children = <Widget>[
      SheetTitle(CalendarHe.bookFor, subtitle: widget.name),
    ];
    if (_enabled == null) {
      children.add(
        _error != null
            ? ErrorView(error: _error!, onRetry: () => unawaited(_load()))
            : const Padding(
                padding: EdgeInsets.all(Space.xl),
                child: Center(child: CircularProgressIndicator.adaptive()),
              ),
      );
    } else if (_enabled == false) {
      children.addAll(_disabled(context));
    } else {
      children.addAll(_enabledBody(context));
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: children,
    );
  }

  List<Widget> _disabled(BuildContext context) {
    final p = context.palette;
    final summary = _settings == null
        ? ''
        : hoursSummary(_settings!.weeklyHours);
    return [
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
            if (summary.isNotEmpty) ...[
              const SizedBox(height: Space.m),
              Row(
                children: [
                  Expanded(
                    child: Text(
                      CalendarHe.defaultHours(summary),
                      key: const Key('customer-book-hours-line'),
                      style: AppText.body,
                    ),
                  ),
                ],
              ),
            ],
            Align(
              alignment: AlignmentDirectional.centerStart,
              child: TextButton.icon(
                key: const Key('customer-book-hours'),
                onPressed: () => unawaited(_openHours()),
                icon: const Icon(Iconsax.clock, size: 18),
                label: const Text(CalendarHe.changeHours),
              ),
            ),
          ],
        ),
      ),
      const SizedBox(height: Space.m),
      PrimaryButton(
        key: const Key('customer-book-primary'),
        label: CalendarHe.enableShort,
        offline: businessContext.offline,
        onPressed: () => unawaited(_enable()),
      ),
    ];
  }

  List<Widget> _enabledBody(BuildContext context) {
    final p = context.palette;
    final link = _mode == CustomerBookingMode.link;
    final day = _day;
    final slots = day == null ? null : _byDay[day];
    return [
      SizedBox(
        width: double.infinity,
        child: SegmentedButton<CustomerBookingMode>(
          key: const Key('customer-book-mode'),
          showSelectedIcon: false,
          style: const ButtonStyle(
            visualDensity: VisualDensity.compact,
            tapTargetSize: MaterialTapTargetSize.padded,
          ),
          segments: [
            for (final (m, label) in const [
              (CustomerBookingMode.suggest, CalendarHe.modeSuggest),
              (CustomerBookingMode.book, CalendarHe.modeBook),
              (CustomerBookingMode.link, CalendarHe.modeLinkShort),
            ])
              ButtonSegment(
                value: m,
                enabled: !_noContact || m == CustomerBookingMode.book,
                label: Text(
                  label,
                  maxLines: 1,
                  softWrap: false,
                  overflow: TextOverflow.fade,
                ),
              ),
          ],
          selected: {_mode},
          onSelectionChanged: (v) => setState(() => _mode = v.first),
        ),
      ),
      if (_noContact)
        Padding(
          padding: const EdgeInsets.only(top: Space.s),
          child: Text(
            CalendarHe.inviteNeedsContact,
            key: const Key('customer-book-no-contact'),
            style: AppText.secondary.copyWith(color: p.muted),
          ),
        ),
      const SizedBox(height: Space.m),
      Text(switch (_mode) {
        CustomerBookingMode.suggest => CalendarHe.suggestHintDays,
        CustomerBookingMode.link => CalendarHe.linkShortHint,
        CustomerBookingMode.book => CalendarHe.bookHintDay,
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
      if (!link) ...[
        const SizedBox(height: Space.m),
        if (_strip.every((d) => d.count == 0))
          Row(
            key: const Key('customer-book-empty'),
            children: [
              Expanded(
                child: Text(
                  CalendarHe.noSlotsHorizon,
                  style: AppText.body.copyWith(color: p.muted),
                ),
              ),
              TextButton(
                onPressed: () => unawaited(_openHours()),
                child: const Text(CalendarHe.hoursButton),
              ),
            ],
          )
        else ...[
          _dayStripView(context),
          const SizedBox(height: Space.m),
          if (_dayLoading && slots == null)
            const Padding(
              padding: EdgeInsets.all(Space.l),
              child: Center(child: CircularProgressIndicator.adaptive()),
            )
          else if (slots == null || slots.isEmpty)
            Text(
              CalendarHe.noTimesThisDay,
              style: AppText.body.copyWith(color: p.muted),
            )
          else
            _timeGrid(context, slots),
        ],
      ],
      if (_mode == CustomerBookingMode.suggest && _picks.isNotEmpty) ...[
        const SizedBox(height: Space.m),
        Wrap(
          spacing: Space.s,
          runSpacing: Space.xs,
          children: [
            for (final (i, s) in _picks.indexed)
              InputChip(
                key: Key('customer-pick-$i'),
                label: Text(slotLabel(s)),
                deleteButtonTooltipMessage: CalendarHe.removePick(slotLabel(s)),
                onDeleted: () => setState(() => _picks.removeAt(i)),
              ),
          ],
        ),
      ],
      if (_mode == CustomerBookingMode.book) ...[
        const SizedBox(height: Space.m),
        TextField(
          key: const Key('customer-book-notes'),
          controller: _notes,
          maxLength: 500,
          minLines: 1,
          maxLines: 3,
          decoration: const InputDecoration(
            labelText: CalendarHe.notesLabel,
            counterText: '',
          ),
        ),
        const SizedBox(height: Space.s),
        Text(
          _confirmLine,
          key: const Key('customer-book-confirm-line'),
          style: AppText.secondary.copyWith(color: p.muted),
        ),
      ],
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
          icon: waPhone(widget.phone) != null ? Iconsax.message : Iconsax.share,
          loadingText: _sending ? CalendarHe.sendInvite : null,
          offline: businessContext.offline,
          onPressed: () => unawaited(_sendInvite()),
        ),
    ];
  }

  /// The same month calendar as "פגישה חדשה" (owner 2026-11-26): days with
  /// free times are tinted; tapping one shows its times below.
  Widget _dayStripView(BuildContext context) {
    final month = _month ?? monthOf(DateTime.parse(_day ?? _strip.first.date));
    return CalendarMonthPicker(
      key: const Key('customer-book-days'),
      month: month,
      days: {
        for (final d in _strip)
          if (d.count > 0) d.date,
      },
      selected: _day,
      onMonth: (m) => setState(() => _month = m),
      onDay: (date) {
        final d = _strip.firstWhere((x) => x.date == date);
        _selectDay(d);
      },
    );
  }

  Widget _timeGrid(BuildContext context, List<FreeSlot> slots) {
    final p = context.palette;
    final suggest = _mode == CustomerBookingMode.suggest;
    Widget cell(int i, FreeSlot s) {
      final selected = suggest
          ? _picks.any((x) => x.start == s.start)
          : _pick?.start == s.start;
      return Semantics(
        button: true,
        selected: selected,
        child: InkWell(
          key: Key('customer-slot-$i'),
          borderRadius: BorderRadius.circular(12),
          onTap: () => suggest ? _toggle(s) : setState(() => _pick = s),
          child: Container(
            height: 44,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: selected ? p.accent : p.surface,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: selected ? p.accent : p.line),
            ),
            child: Text(
              s.time,
              textDirection: TextDirection.ltr,
              style: AppText.body.copyWith(
                color: selected ? p.accentInk : p.ink,
                fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
              ),
            ),
          ),
        ),
      );
    }

    final rows = <Widget>[];
    for (var start = 0; start < slots.length; start += 4) {
      if (rows.isNotEmpty) rows.add(const SizedBox(height: Space.s));
      rows.add(
        Row(
          children: [
            for (var i = start; i < start + 4; i++) ...[
              if (i > start) const SizedBox(width: Space.s),
              Expanded(
                child: i < slots.length ? cell(i, slots[i]) : const SizedBox(),
              ),
            ],
          ],
        ),
      );
    }
    return Column(
      key: const Key('customer-book-times'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: rows,
    );
  }
}

// "פגישה חדשה" (spec §9, like iOS's new-event sheet): "ביטול" · title ·
// "הוספה" on top; the first field is the customer (from the customers list);
// then date and time, each opening its picker in place — a small month with
// the bookable days, then that day's free times as rounded buttons
// (GET /calendar/free-slots); an optional note. Opened from "+" or a
// long-press on an empty hour (that day and time are preselected).
// "הוספה" books it for the customer (POST /calendar/bookings, CONFIRMED).

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:iconsax_flutter/iconsax_flutter.dart';

import '../../api/client.dart' show ApiException;
import '../../api/models/models.dart' show Customer;
import '../../ui/ds.dart';
import '../../util/labels/calendar_he.dart';
import '../people/sheets/s2_customer.dart' show showCustomerSheet;
import 'calendar_api.dart';
import 'calendar_layout.dart';

/// The customer picker (tests replace it).
Future<Customer?> Function(BuildContext context) pickCalendarCustomer = (c) =>
    showCustomerSheet(c, openExistingCard: false);

Future<Booking?> showNewBookingSheet(BuildContext context, {DateTime? at}) =>
    showAppSheet<Booking>(context, builder: (_) => NewBookingSheet(at: at));

enum _Open { none, date, time }

class NewBookingSheet extends StatefulWidget {
  const NewBookingSheet({super.key, this.at});

  /// A long-pressed hour: preselects that day and the nearest free time.
  final DateTime? at;

  @override
  State<NewBookingSheet> createState() => _NewBookingSheetState();
}

class _NewBookingSheetState extends State<NewBookingSheet> {
  Customer? _customer;
  List<FreeDay>? _days;
  String? _date;
  List<FreeSlot>? _slots;
  FreeSlot? _slot;
  _Open _open = _Open.none;
  DateTime _month = monthOf(DateTime.now());
  final _notes = TextEditingController();
  bool _saving = false;
  bool? _enabled;
  String? _error;

  @override
  void initState() {
    super.initState();
    unawaited(_loadDays());
  }

  @override
  void dispose() {
    _notes.dispose();
    super.dispose();
  }

  Future<void> _loadDays() async {
    try {
      final f = await fetchFreeSlots(limit: 1);
      if (!mounted) return;
      final days = [
        for (final d in f.days)
          if (d.count > 0) d,
      ];
      setState(() {
        _enabled = f.enabled;
        _days = days;
      });
      final at = widget.at;
      final wanted = at == null ? null : ymd(dayOf(at));
      final first = days.any((d) => d.date == wanted)
          ? wanted
          : days.firstOrNull?.date;
      if (first != null) await _pickDate(first, keepOpen: false);
    } on Object catch (e) {
      if (mounted) setState(() => _error = _message(e));
    }
  }

  Future<void> _pickDate(String date, {bool keepOpen = true}) async {
    setState(() {
      _date = date;
      _slots = null;
      _slot = null;
      _month = monthOf(DateTime.parse(date));
    });
    try {
      final f = await fetchFreeSlots(date: date, limit: 60);
      if (!mounted || _date != date) return;
      final at = widget.at;
      setState(() {
        _slots = f.slots;
        _slot = at != null && ymd(dayOf(at)) == date
            ? slotNear(f.slots, at)
            : (keepOpen ? null : f.slots.firstOrNull);
        if (keepOpen) _open = _Open.time;
      });
    } on Object catch (e) {
      if (mounted) setState(() => _error = _message(e));
    }
  }

  String _message(Object e) =>
      e is ApiException ? CalendarHe.error(e.code) : CalendarHe.error(null);

  Future<void> _pickCustomer() async {
    final c = await pickCalendarCustomer(context);
    if (c == null || !mounted) return;
    setState(() {
      _customer = c;
      _error = null;
    });
  }

  Future<void> _add() async {
    final c = _customer;
    final s = _slot;
    if (c == null || s == null || _saving) return;
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      final booking = await bookForCustomer(c.id, s.start, notes: _notes.text);
      if (mounted) Navigator.of(context).pop(booking);
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() {
        _saving = false;
        _error = CalendarHe.error(e.code);
      });
      if (e.code == 'SLOT_TAKEN' && _date != null) {
        await _pickDate(_date!);
      }
    } on Object catch (e) {
      if (mounted) {
        setState(() {
          _saving = false;
          _error = _message(e);
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final ready = _customer != null && _slot != null && !_saving;
    final date = _date == null ? null : DateTime.parse(_date!);
    return Column(
      key: const Key('new-booking'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          children: [
            TextButton(
              key: const Key('new-booking-cancel'),
              onPressed: () => Navigator.of(context).pop(),
              child: const Text(CalendarHe.cancelSheet),
            ),
            const Expanded(
              child: Text(
                CalendarHe.newMeeting,
                textAlign: TextAlign.center,
                style: AppText.headline,
              ),
            ),
            TextButton(
              key: const Key('new-booking-add'),
              onPressed: ready ? () => unawaited(_add()) : null,
              child: _saving
                  ? const SizedBox.square(
                      dimension: 18,
                      child: CircularProgressIndicator.adaptive(strokeWidth: 2),
                    )
                  : Text(
                      CalendarHe.add,
                      style: const TextStyle(fontWeight: FontWeight.w800),
                    ),
            ),
          ],
        ),
        const SizedBox(height: Space.m),
        _Group(
          children: [
            _FieldRow(
              key: const Key('new-booking-customer'),
              label: CalendarHe.customer,
              value: _customer?.name,
              placeholder: CalendarHe.pickCustomer,
              onTap: () => unawaited(_pickCustomer()),
            ),
          ],
        ),
        const SizedBox(height: Space.m),
        if (_enabled == false)
          Padding(
            padding: const EdgeInsets.only(bottom: Space.m),
            child: Text(
              CalendarHe.disabledBody,
              key: const Key('new-booking-disabled'),
              style: AppText.secondary.copyWith(color: p.warn),
            ),
          ),
        _Group(
          children: [
            _FieldRow(
              key: const Key('new-booking-date'),
              label: CalendarHe.date,
              value: date == null ? null : CalendarHe.longDay(date),
              placeholder: _days == null ? '…' : CalendarHe.pickDate,
              chip: true,
              open: _open == _Open.date,
              onTap: _days == null || _days!.isEmpty
                  ? null
                  : () => setState(
                      () =>
                          _open = _open == _Open.date ? _Open.none : _Open.date,
                    ),
            ),
            AnimatedSize(
              duration: context.motion(220),
              curve: Curves.easeOut,
              child: _open == _Open.date
                  ? _PickerMonth(
                      month: _month,
                      days: {
                        for (final d in _days ?? const <FreeDay>[]) d.date,
                      },
                      selected: _date,
                      onMonth: (m) => setState(() => _month = m),
                      onDay: (d) {
                        HapticFeedback.selectionClick();
                        unawaited(_pickDate(d));
                      },
                    )
                  : const SizedBox(width: double.infinity),
            ),
            Divider(height: 1, color: p.line, indent: Space.l),
            _FieldRow(
              key: const Key('new-booking-time'),
              label: CalendarHe.time,
              value: _slot?.time,
              placeholder: CalendarHe.pickTime,
              chip: true,
              ltr: true,
              open: _open == _Open.time,
              onTap: _slots == null
                  ? null
                  : () => setState(
                      () =>
                          _open = _open == _Open.time ? _Open.none : _Open.time,
                    ),
            ),
            AnimatedSize(
              duration: context.motion(220),
              curve: Curves.easeOut,
              child: _open == _Open.time && _slots != null
                  ? Padding(
                      padding: const EdgeInsets.fromLTRB(
                        Space.l,
                        0,
                        Space.l,
                        Space.l,
                      ),
                      child: _slots!.isEmpty
                          ? Text(
                              CalendarHe.noTimesThisDay,
                              style: AppText.secondary.copyWith(color: p.muted),
                            )
                          : _TimeGrid(
                              slots: _slots!,
                              selected: _slot,
                              onPick: (s) {
                                HapticFeedback.selectionClick();
                                setState(() {
                                  _slot = s;
                                  _open = _Open.none;
                                });
                              },
                            ),
                    )
                  : const SizedBox(width: double.infinity),
            ),
          ],
        ),
        if (_days != null && _days!.isEmpty && _enabled != false)
          Padding(
            padding: const EdgeInsets.only(top: Space.s),
            child: Text(
              CalendarHe.noSlotsHorizon,
              style: AppText.secondary.copyWith(color: p.muted),
            ),
          ),
        const SizedBox(height: Space.m),
        TextField(
          key: const Key('new-booking-notes'),
          controller: _notes,
          maxLength: 1000,
          minLines: 1,
          maxLines: 4,
          decoration: InputDecoration(
            labelText: CalendarHe.notes,
            hintText: CalendarHe.notesHint,
            counterText: '',
          ),
        ),
        if (_customer == null)
          Padding(
            padding: const EdgeInsets.only(top: Space.s),
            child: Text(
              CalendarHe.noCustomer,
              style: AppText.caption.copyWith(fontSize: 13, color: p.muted),
            ),
          ),
        if (_error != null)
          Padding(
            padding: const EdgeInsets.only(top: Space.s),
            child: Text(
              _error!,
              key: const Key('new-booking-error'),
              style: AppText.secondary.copyWith(color: p.danger),
            ),
          ),
      ],
    );
  }
}

class _Group extends StatelessWidget {
  const _Group({required this.children});
  final List<Widget> children;

  @override
  Widget build(BuildContext context) => Material(
    color: context.palette.canvas,
    borderRadius: BorderRadius.circular(18),
    clipBehavior: Clip.antiAlias,
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: children,
    ),
  );
}

class _FieldRow extends StatelessWidget {
  const _FieldRow({
    super.key,
    required this.label,
    required this.value,
    required this.placeholder,
    required this.onTap,
    this.chip = false,
    this.open = false,
    this.ltr = false,
  });

  final String label;
  final String? value;
  final String placeholder;
  final VoidCallback? onTap;
  final bool chip;
  final bool open;
  final bool ltr;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final text = Text(
      value ?? placeholder,
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      textDirection: ltr && value != null ? TextDirection.ltr : null,
      style: AppText.body.copyWith(
        color: value == null ? p.muted : (open ? p.accentInk : p.ink),
        fontWeight: value == null ? FontWeight.w400 : FontWeight.w600,
      ),
    );
    return InkWell(
      onTap: onTap,
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: Hit.min + 8),
        child: Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: Space.l,
            vertical: Space.s,
          ),
          child: Row(
            children: [
              Text(label, style: AppText.body),
              const SizedBox(width: Space.m),
              Expanded(
                child: Align(
                  alignment: AlignmentDirectional.centerEnd,
                  child: chip
                      ? Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: Space.m,
                            vertical: 6,
                          ),
                          decoration: BoxDecoration(
                            color: open ? p.accent : p.surface,
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: text,
                        )
                      : Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Flexible(child: text),
                            const SizedBox(width: Space.xs),
                            Icon(
                              Iconsax.arrow_left_2,
                              size: 16,
                              color: p.muted,
                            ),
                          ],
                        ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// The inline date picker: one month, bookable days bold, the rest grey.
class _PickerMonth extends StatelessWidget {
  const _PickerMonth({
    required this.month,
    required this.days,
    required this.selected,
    required this.onMonth,
    required this.onDay,
  });

  final DateTime month;
  final Set<String> days;
  final String? selected;
  final ValueChanged<DateTime> onMonth;
  final ValueChanged<String> onDay;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final sorted = days.toList()..sort();
    final first = sorted.isEmpty
        ? month
        : monthOf(DateTime.parse(sorted.first));
    final last = sorted.isEmpty ? month : monthOf(DateTime.parse(sorted.last));
    final today = dayOf(DateTime.now());
    final blanks = leadingBlanks(month);
    final length = daysInMonth(month);
    return Padding(
      key: const Key('new-booking-month'),
      padding: const EdgeInsets.fromLTRB(Space.s, 0, Space.s, Space.m),
      child: Column(
        children: [
          Row(
            children: [
              const SizedBox(width: Space.s),
              Expanded(
                child: Text(
                  CalendarHe.monthYear(month),
                  style: AppText.headline,
                ),
              ),
              IconButton(
                key: const Key('new-booking-prev-month'),
                onPressed: month.isAfter(first)
                    ? () => onMonth(addMonths(month, -1))
                    : null,
                icon: const Icon(Iconsax.arrow_right_3, size: 20),
              ),
              IconButton(
                key: const Key('new-booking-next-month'),
                onPressed: month.isBefore(last)
                    ? () => onMonth(addMonths(month, 1))
                    : null,
                icon: const Icon(Iconsax.arrow_left_2, size: 20),
              ),
            ],
          ),
          Row(
            children: [
              for (final l in CalendarHe.weekdayLetters)
                Expanded(
                  child: Text(
                    l,
                    textAlign: TextAlign.center,
                    style: AppText.caption.copyWith(
                      fontSize: 12,
                      color: p.muted,
                    ),
                  ),
                ),
            ],
          ),
          for (var r = 0; r < weekRows(month); r++)
            Row(
              children: [
                for (var c = 0; c < 7; c++)
                  Expanded(
                    child: Builder(
                      builder: (context) {
                        final n = r * 7 + c - blanks + 1;
                        if (n < 1 || n > length) {
                          return const SizedBox(height: 42);
                        }
                        final d = DateTime(month.year, month.month, n);
                        final key = ymd(d);
                        final free = days.contains(key);
                        final sel = key == selected;
                        final isToday = d == today;
                        return GestureDetector(
                          key: Key('new-booking-day-$key'),
                          behavior: HitTestBehavior.opaque,
                          onTap: free ? () => onDay(key) : null,
                          child: SizedBox(
                            height: 42,
                            child: Center(
                              child: Container(
                                width: 36,
                                height: 36,
                                alignment: Alignment.center,
                                decoration: BoxDecoration(
                                  shape: BoxShape.circle,
                                  color: sel
                                      ? (isToday ? p.accent : p.charcoal)
                                      : free
                                      ? p.tint(p.ok)
                                      : null,
                                ),
                                child: Text(
                                  '$n',
                                  style: AppText.body.copyWith(
                                    fontWeight: free || isToday
                                        ? FontWeight.w700
                                        : FontWeight.w400,
                                    color: sel
                                        ? (isToday ? p.accentInk : p.onCharcoal)
                                        : free
                                        ? p.ink
                                        : p.muted.withValues(alpha: .6),
                                  ),
                                ),
                              ),
                            ),
                          ),
                        );
                      },
                    ),
                  ),
              ],
            ),
        ],
      ),
    );
  }
}

/// The day's free times as rounded buttons, 4 per row.
class _TimeGrid extends StatelessWidget {
  const _TimeGrid({
    required this.slots,
    required this.selected,
    required this.onPick,
  });

  final List<FreeSlot> slots;
  final FreeSlot? selected;
  final ValueChanged<FreeSlot> onPick;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return LayoutBuilder(
      builder: (context, c) {
        final w = (c.maxWidth - 3 * Space.s) / 4;
        return Wrap(
          spacing: Space.s,
          runSpacing: Space.s,
          children: [
            for (var i = 0; i < slots.length; i++)
              SizedBox(
                width: w,
                child: Material(
                  color: slots[i].start == selected?.start
                      ? p.accent
                      : p.surface,
                  shape: StadiumBorder(
                    side: BorderSide(
                      color: slots[i].start == selected?.start
                          ? p.accent
                          : p.line,
                    ),
                  ),
                  child: InkWell(
                    key: Key('new-booking-slot-$i'),
                    customBorder: const StadiumBorder(),
                    onTap: () => onPick(slots[i]),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(vertical: 10),
                      child: Text(
                        slots[i].time,
                        textAlign: TextAlign.center,
                        textDirection: TextDirection.ltr,
                        style: AppText.body.copyWith(
                          fontWeight: FontWeight.w600,
                          color: slots[i].start == selected?.start
                              ? p.accentInk
                              : p.ink,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
          ],
        );
      },
    );
  }
}

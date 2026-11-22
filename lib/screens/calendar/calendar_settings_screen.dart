// "הגדרות יומן": on/off, the public link (share / new link), working hours per
// weekday (up to two ranges: a break), vacation dates, manual approval,
// blocked clients, meeting length / break / notice / how far ahead, notifications
// (new booking, reminder before a meeting) and the phone calendars to read
// from and write to. Server settings save with one button; the phone choices
// apply at once (they live on this phone only).

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:iconsax_flutter/iconsax_flutter.dart';

import '../../state/business_context.dart';
import '../../ui/app_page_route.dart';
import '../../ui/ds.dart';
import '../../util/labels/calendar_he.dart';
import '../business/business_template.dart';
import '../document/dialogs.dart' show toast;
import 'blocked_contacts_screen.dart';
import 'calendar_api.dart';
import 'calendar_sync.dart';
import 'device_calendar.dart';

Future<void> openCalendarSettings(BuildContext context, {CalendarSync? sync}) =>
    Navigator.of(context).push(
      AppPageRoute<void>(
        builder: (_) => CalendarSettingsScreen(sync: sync),
        settings: const RouteSettings(name: '/calendar/settings'),
      ),
    );

const slotOptions = [15, 20, 30, 45, 60, 90];
const bufferOptions = [0, 5, 10, 15, 30];
const noticeOptions = [0, 60, 120, 240, 1440];
const aheadOptions = [7, 14, 30, 60];
const reminderOptions = [0, 5, 10, 15, 30, 60];

/// A break per day: two ranges at most here (the server allows 4).
const maxRangesPerDay = 2;
const maxBlockedRanges = 30;

int _minutes(String hm) {
  final p = hm.split(':');
  return int.parse(p[0]) * 60 + int.parse(p[1]);
}

String _hm(int minutes) =>
    '${(minutes ~/ 60).toString().padLeft(2, '0')}:${(minutes % 60).toString().padLeft(2, '0')}';

/// Ranges are sorted, each non-empty, and do not touch or overlap.
bool validRanges(List<TimeRangeHm> ranges) {
  for (var i = 0; i < ranges.length; i++) {
    if (_minutes(ranges[i].end) <= _minutes(ranges[i].start)) return false;
    if (i > 0 && _minutes(ranges[i].start) <= _minutes(ranges[i - 1].end)) {
      return false;
    }
  }
  return true;
}

/// "הוספת הפסקה": splits the day's range around its middle hour with an hour
/// off (09:00–17:00 → 09:00–13:00 + 14:00–17:00); null when too short.
List<TimeRangeHm>? withBreak(TimeRangeHm r) {
  final s = _minutes(r.start);
  final e = _minutes(r.end);
  final mid = ((s + e) ~/ 2) ~/ 60 * 60;
  final next = [
    TimeRangeHm(r.start, _hm(mid)),
    TimeRangeHm(_hm(mid + 60), r.end),
  ];
  return validRanges(next) ? next : null;
}

/// "dd.MM" (or "dd.MM – dd.MM") for a blocked range.
String blockedRangeLabel(BlockedRange r) {
  String d(String ymd) {
    final p = ymd.split('-');
    return p.length == 3 ? '${p[2]}.${p[1]}.${p[0]}' : ymd;
  }

  return r.from == r.to ? d(r.from) : '${d(r.from)} – ${d(r.to)}';
}

class CalendarSettingsScreen extends StatefulWidget {
  const CalendarSettingsScreen({super.key, this.sync});
  final CalendarSync? sync;

  @override
  State<CalendarSettingsScreen> createState() => _CalendarSettingsScreenState();
}

class _CalendarSettingsScreenState extends State<CalendarSettingsScreen> {
  CalendarSync get _sync => widget.sync ?? calendarSync;
  CalendarSettings? _s;
  Object? _error;
  bool _saving = false;
  List<DeviceCalendarInfo> _calendars = const [];

  // Editable copy.
  late bool _enabled;
  late List<DayHours> _hours;
  late int _slot;
  late int _buffer;
  late int _notice;
  late int _ahead;
  late bool _notifyNew;
  late int _reminder;
  late bool _requireApproval;
  late List<BlockedRange> _blocked;
  final _title = TextEditingController();

  @override
  void initState() {
    super.initState();
    _sync.addListener(_changed);
    unawaited(_load());
  }

  @override
  void dispose() {
    _sync.removeListener(_changed);
    _title.dispose();
    super.dispose();
  }

  void _changed() {
    if (mounted) setState(() {});
  }

  void _adopt(CalendarSettings s) {
    _s = s;
    _enabled = s.enabled;
    _hours = [
      for (var d = 0; d < 7; d++)
        s.weeklyHours.firstWhere(
          (h) => h.day == d,
          orElse: () => DayHours(d, const []),
        ),
    ];
    _slot = s.slotMinutes;
    _buffer = s.bufferMinutes;
    _notice = s.minNoticeMinutes;
    _ahead = s.maxDaysAhead;
    _notifyNew = s.notifyNewBooking;
    _reminder = s.reminderMinutes;
    _requireApproval = s.requireApproval;
    _blocked = [...s.blockedDates];
    _title.text = s.meetingTitle ?? '';
  }

  Future<void> _load() async {
    try {
      final s = await fetchCalendarSettings();
      await _sync.loadPrefs();
      final access = _sync.device.supported
          ? await _sync.device.status()
          : CalendarAccess.unsupported;
      final cals = access == CalendarAccess.full
          ? await _sync.device.calendars()
          : const <DeviceCalendarInfo>[];
      if (!mounted) return;
      setState(() {
        _adopt(s);
        _calendars = cals;
        _error = null;
      });
    } on Object catch (e) {
      if (mounted) setState(() => _error = e);
    }
  }

  Future<void> _save() async {
    if (_saving) return;
    setState(() => _saving = true);
    try {
      final s = await saveCalendarSettings({
        'enabled': _enabled,
        'weeklyHours': [for (final h in _hours) h.toJson()],
        'slotMinutes': _slot,
        'bufferMinutes': _buffer,
        'minNoticeMinutes': _notice,
        'maxDaysAhead': _ahead,
        'meetingTitle': _title.text.trim(),
        'notifyNewBooking': _notifyNew,
        'reminderMinutes': _reminder,
        'requireApproval': _requireApproval,
        'blockedDates': [for (final r in _blocked) r.toJson()],
      });
      if (!mounted) return;
      setState(() => _adopt(s));
      toast(context, CalendarHe.saved);
      unawaited(_sync.sync(force: true));
    } on Object catch (e) {
      if (mounted) showErrorSnack(context, e);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _regenerate() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text(CalendarHe.regenerateTitle),
        content: const Text(CalendarHe.regenerateBody),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(c, false),
            child: const Text(CalendarHe.keep),
          ),
          TextButton(
            key: const Key('calendar-regenerate-confirm'),
            onPressed: () => Navigator.pop(c, true),
            child: const Text(CalendarHe.regenerate),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    try {
      final s = await regenerateCalendarLink();
      if (!mounted) return;
      setState(() => _s = s);
      toast(context, CalendarHe.regenerated);
    } on Object catch (e) {
      if (mounted) showErrorSnack(context, e);
    }
  }

  Future<String?> _pickTime(String current) async {
    final parts = current.split(':');
    final picked = await showTimePicker(
      context: context,
      initialTime: TimeOfDay(
        hour: int.parse(parts[0]) % 24,
        minute: int.parse(parts[1]),
      ),
      builder: (c, child) => MediaQuery(
        data: MediaQuery.of(c).copyWith(alwaysUse24HourFormat: true),
        child: child!,
      ),
    );
    if (picked == null) return null;
    return '${picked.hour.toString().padLeft(2, '0')}:${picked.minute.toString().padLeft(2, '0')}';
  }

  /// The start or end of the day's range [i].
  Future<void> _editRange(int day, int i, {required bool start}) async {
    final ranges = [..._hours[day].ranges];
    final r = ranges[i];
    final picked = await _pickTime(start ? r.start : r.end);
    if (picked == null || !mounted) return;
    ranges[i] = start
        ? TimeRangeHm(picked, r.end)
        : TimeRangeHm(r.start, picked);
    if (!validRanges(ranges)) {
      toast(context, CalendarHe.error('VALIDATION'));
      return;
    }
    setState(() => _hours[day] = DayHours(day, ranges));
  }

  void _addBreak(int day) {
    final ranges = _hours[day].ranges;
    final split = withBreak(ranges.last);
    if (split == null) {
      toast(context, CalendarHe.error('VALIDATION'));
      return;
    }
    setState(
      () => _hours[day] = DayHours(day, [
        ...ranges.sublist(0, ranges.length - 1),
        ...split,
      ]),
    );
  }

  /// Removing the break before range [i] joins it with the one before.
  void _removeBreak(int day, int i) {
    final ranges = [..._hours[day].ranges];
    ranges[i - 1] = TimeRangeHm(ranges[i - 1].start, ranges[i].end);
    ranges.removeAt(i);
    setState(() => _hours[day] = DayHours(day, ranges));
  }

  Future<void> _addBlocked() async {
    if (_blocked.length >= maxBlockedRanges) {
      toast(context, CalendarHe.tooManyBlockedDates);
      return;
    }
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final picked = await showDateRangePicker(
      context: context,
      firstDate: today,
      lastDate: today.add(const Duration(days: 730)),
      helpText: CalendarHe.blockedDates,
    );
    if (picked == null || !mounted) return;
    setState(
      () => _blocked = [
        ..._blocked,
        BlockedRange(ymd(picked.start), ymd(picked.end)),
      ]..sort((a, b) => a.from.compareTo(b.from)),
    );
  }

  @override
  Widget build(BuildContext context) {
    final s = _s;
    final p = context.palette;
    if (s == null) {
      return BusinessPage(
        title: CalendarHe.settings,
        children: [
          if (_error != null)
            ErrorView(error: _error!, onRetry: () => unawaited(_load()))
          else
            const Padding(
              padding: EdgeInsets.only(top: Space.xl),
              child: Center(child: CircularProgressIndicator.adaptive()),
            ),
        ],
      );
    }
    final prefs = _sync.prefs;
    return BusinessPage(
      title: CalendarHe.settings,
      bottom: BottomActionArea(
        child: PrimaryButton(
          key: const Key('calendar-save'),
          label: CalendarHe.save,
          loadingText: _saving ? CalendarHe.save : null,
          offline: businessContext.offline,
          onPressed: () => unawaited(_save()),
        ),
      ),
      children: [
        SwitchListTile.adaptive(
          key: const Key('calendar-enabled'),
          contentPadding: EdgeInsets.zero,
          title: const Text(CalendarHe.enabled),
          subtitle: const Text(CalendarHe.enabledHint),
          value: _enabled,
          onChanged: (v) => setState(() => _enabled = v),
        ),
        const RowGroupGap(),
        _Label(CalendarHe.link),
        SelectableText(
          s.bookingUrl,
          key: const Key('calendar-settings-link'),
          textDirection: TextDirection.ltr,
          style: AppText.secondary.copyWith(color: p.muted),
        ),
        Align(
          alignment: AlignmentDirectional.centerStart,
          child: TextButton.icon(
            key: const Key('calendar-regenerate'),
            onPressed: () => unawaited(_regenerate()),
            icon: const Icon(Iconsax.refresh),
            label: const Text(CalendarHe.regenerate),
          ),
        ),
        const RowGroupGap(),
        _Label(CalendarHe.hours),
        for (var d = 0; d < 7; d++)
          _DayRow(
            key: Key('calendar-day-$d'),
            label: CalendarHe.days[d],
            hours: _hours[d],
            onToggle: (open) => setState(
              () => _hours[d] = DayHours(
                d,
                open ? const [TimeRangeHm('09:00', '17:00')] : const [],
              ),
            ),
            onTime: (i, start) => unawaited(_editRange(d, i, start: start)),
            onAddBreak: () => _addBreak(d),
            onRemoveBreak: (i) => _removeBreak(d, i),
          ),
        const RowGroupGap(),
        _Label(CalendarHe.blockedDates),
        Text(
          CalendarHe.blockedDatesHint,
          style: AppText.secondary.copyWith(color: p.muted),
        ),
        if (_blocked.isEmpty)
          Padding(
            padding: const EdgeInsets.only(top: Space.s),
            child: Text(
              CalendarHe.noBlockedDates,
              style: AppText.secondary.copyWith(color: p.muted),
            ),
          ),
        for (final (i, r) in _blocked.indexed)
          ListTile(
            key: Key('calendar-blocked-$i'),
            contentPadding: EdgeInsets.zero,
            leading: const Icon(Iconsax.calendar_remove),
            title: Text(blockedRangeLabel(r), textDirection: TextDirection.ltr),
            trailing: IconButton(
              key: Key('calendar-blocked-remove-$i'),
              tooltip: CalendarHe.removeBlockedDates,
              icon: Icon(Iconsax.trash, color: p.danger),
              onPressed: () =>
                  setState(() => _blocked = [..._blocked]..removeAt(i)),
            ),
          ),
        Align(
          alignment: AlignmentDirectional.centerStart,
          child: TextButton.icon(
            key: const Key('calendar-blocked-add'),
            onPressed: () => unawaited(_addBlocked()),
            icon: const Icon(Iconsax.add),
            label: const Text(CalendarHe.addBlockedDates),
          ),
        ),
        const RowGroupGap(),
        SwitchListTile.adaptive(
          key: const Key('calendar-require-approval'),
          contentPadding: EdgeInsets.zero,
          title: const Text(CalendarHe.requireApproval),
          subtitle: const Text(CalendarHe.requireApprovalHint),
          value: _requireApproval,
          onChanged: (v) => setState(() => _requireApproval = v),
        ),
        ListTile(
          key: const Key('calendar-blocked-clients'),
          contentPadding: EdgeInsets.zero,
          leading: const Icon(Iconsax.user_remove),
          title: const Text(CalendarHe.blockedClients),
          subtitle: const Text(CalendarHe.blockedClientsHint),
          trailing: const Icon(Iconsax.arrow_left_2),
          onTap: () => unawaited(openBlockedContacts(context)),
        ),
        const RowGroupGap(),
        _Label(CalendarHe.meetingTitle),
        TextField(
          key: const Key('calendar-title'),
          controller: _title,
          maxLength: 80,
          decoration: InputDecoration(
            hintText: CalendarHe.meetingTitleHint(businessContext.displayName),
          ),
        ),
        _Label(CalendarHe.slot),
        ChipRow<int>(
          key: const Key('calendar-slot'),
          padding: EdgeInsets.zero,
          options: [
            for (final m in slotOptions) ChipOption(m, CalendarHe.minutes(m)),
          ],
          selected: _slot,
          onSelected: (v) => setState(() => _slot = v),
        ),
        _Label(CalendarHe.buffer),
        ChipRow<int>(
          key: const Key('calendar-buffer'),
          padding: EdgeInsets.zero,
          options: [
            for (final m in bufferOptions)
              ChipOption(
                m,
                m == 0 ? CalendarHe.noBuffer : CalendarHe.minutes(m),
              ),
          ],
          selected: _buffer,
          onSelected: (v) => setState(() => _buffer = v),
        ),
        _Label(CalendarHe.notice),
        ChipRow<int>(
          key: const Key('calendar-notice'),
          padding: EdgeInsets.zero,
          options: [
            for (final m in noticeOptions)
              ChipOption(m, CalendarHe.noticeLabel(m)),
          ],
          selected: _notice,
          onSelected: (v) => setState(() => _notice = v),
        ),
        _Label(CalendarHe.ahead),
        ChipRow<int>(
          key: const Key('calendar-ahead'),
          padding: EdgeInsets.zero,
          options: [
            for (final d in aheadOptions)
              ChipOption(d, CalendarHe.aheadLabel(d)),
          ],
          selected: _ahead,
          onSelected: (v) => setState(() => _ahead = v),
        ),
        const RowGroupGap(),
        _Label(CalendarHe.notifications),
        SwitchListTile.adaptive(
          key: const Key('calendar-notify-new'),
          contentPadding: EdgeInsets.zero,
          title: const Text(CalendarHe.notifyNew),
          subtitle: const Text(CalendarHe.notifyNewHint),
          value: _notifyNew,
          onChanged: (v) => setState(() => _notifyNew = v),
        ),
        _Label(CalendarHe.reminder),
        ChipRow<int>(
          key: const Key('calendar-reminder'),
          padding: EdgeInsets.zero,
          options: [
            for (final m in reminderOptions)
              ChipOption(
                m,
                m == 0 ? CalendarHe.reminderOff : CalendarHe.minutes(m),
              ),
          ],
          selected: _reminder,
          onSelected: (v) => setState(() => _reminder = v),
        ),
        Padding(
          padding: const EdgeInsets.only(top: Space.s),
          child: Text(
            CalendarHe.reminderHint,
            style: AppText.secondary.copyWith(color: p.muted),
          ),
        ),
        if (_sync.device.supported) ...[
          const RowGroupGap(),
          _Label(CalendarHe.calendars),
          if (prefs == null || !prefs.connected)
            Align(
              alignment: AlignmentDirectional.centerStart,
              child: FilledButton(
                key: const Key('calendar-settings-connect'),
                onPressed: () async {
                  await _sync.connect();
                  await _load();
                },
                child: const Text(CalendarHe.connectButton),
              ),
            )
          else ...[
            Text(
              CalendarHe.freshness,
              style: AppText.secondary.copyWith(color: p.muted),
            ),
            _Label(CalendarHe.readFrom),
            for (final c in _calendars)
              CheckboxListTile(
                key: Key('calendar-read-${c.id}'),
                contentPadding: EdgeInsets.zero,
                controlAffinity: ListTileControlAffinity.leading,
                value: prefs.read.contains(c.id),
                title: Text(c.title),
                subtitle: Text(c.account),
                secondary: _Dot(c.color),
                onChanged: (v) {
                  final next = [...prefs.read];
                  if (v == true) {
                    next.add(c.id);
                  } else {
                    next.remove(c.id);
                  }
                  unawaited(_sync.choose(read: next));
                },
              ),
            _Label(CalendarHe.writeTo),
            RadioGroup<String?>(
              groupValue: prefs.write,
              onChanged: (v) => unawaited(
                v == null
                    ? _sync.choose(clearWrite: true)
                    : _sync.choose(write: v),
              ),
              child: Column(
                children: [
                  for (final c in _calendars.where((c) => c.writable))
                    RadioListTile<String?>(
                      key: Key('calendar-write-${c.id}'),
                      contentPadding: EdgeInsets.zero,
                      value: c.id,
                      title: Text(c.title),
                      subtitle: Text(c.account),
                      secondary: _Dot(c.color),
                    ),
                  const RadioListTile<String?>(
                    key: Key('calendar-write-none'),
                    contentPadding: EdgeInsets.zero,
                    value: null,
                    title: Text(CalendarHe.noWrite),
                  ),
                ],
              ),
            ),
            Align(
              alignment: AlignmentDirectional.centerStart,
              child: TextButton(
                key: const Key('calendar-disconnect'),
                onPressed: () async {
                  await _sync.disconnect();
                  if (context.mounted) toast(context, CalendarHe.disconnected);
                },
                child: Text(
                  CalendarHe.disconnect,
                  style: TextStyle(color: p.danger),
                ),
              ),
            ),
          ],
        ],
      ],
    );
  }
}

class _Label extends StatelessWidget {
  const _Label(this.text);
  final String text;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(top: Space.m, bottom: Space.s),
    child: Text(text, style: AppText.headline),
  );
}

class _Dot extends StatelessWidget {
  const _Dot(this.hex);
  final String hex;

  @override
  Widget build(BuildContext context) {
    final v = int.tryParse(hex.replaceFirst('#', ''), radix: 16) ?? 0x8A948F;
    return CircleAvatar(radius: 6, backgroundColor: Color(0xFF000000 | v));
  }
}

class _DayRow extends StatelessWidget {
  const _DayRow({
    super.key,
    required this.label,
    required this.hours,
    required this.onToggle,
    required this.onTime,
    required this.onAddBreak,
    required this.onRemoveBreak,
  });

  final String label;
  final DayHours hours;
  final ValueChanged<bool> onToggle;
  final void Function(int index, bool start) onTime;
  final VoidCallback onAddBreak;
  final ValueChanged<int> onRemoveBreak;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final open = hours.open;
    final ranges = hours.ranges;
    // Scales down on a narrow phone instead of overflowing.
    Widget range(int i) => FittedBox(
      fit: BoxFit.scaleDown,
      alignment: AlignmentDirectional.centerStart,
      child: Row(
        key: Key('calendar-day-${hours.day}-range-$i'),
        mainAxisSize: MainAxisSize.min,
        children: [
          _TimeButton(text: ranges[i].start, onTap: () => onTime(i, true)),
          Text(' – ', style: AppText.body.copyWith(color: p.muted)),
          _TimeButton(text: ranges[i].end, onTap: () => onTime(i, false)),
          if (i > 0)
            IconButton(
              key: Key('calendar-day-${hours.day}-remove-break-$i'),
              tooltip: CalendarHe.removeBreak,
              icon: Icon(Iconsax.minus_cirlce, size: 20, color: p.danger),
              onPressed: () => onRemoveBreak(i),
            ),
        ],
      ),
    );
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 64,
            child: Padding(
              padding: const EdgeInsets.only(top: Space.s),
              child: Text(label, style: AppText.body),
            ),
          ),
          Switch.adaptive(value: open, onChanged: onToggle),
          const SizedBox(width: Space.s),
          if (open)
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  for (var i = 0; i < ranges.length; i++)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 2),
                      child: range(i),
                    ),
                  if (ranges.length < maxRangesPerDay)
                    TextButton.icon(
                      key: Key('calendar-day-${hours.day}-add-break'),
                      style: TextButton.styleFrom(
                        padding: EdgeInsets.zero,
                        visualDensity: VisualDensity.compact,
                      ),
                      onPressed: onAddBreak,
                      icon: const Icon(Iconsax.add, size: 16),
                      label: Text(
                        CalendarHe.addBreak,
                        style: AppText.secondary.copyWith(color: p.ink),
                      ),
                    ),
                ],
              ),
            )
          else
            Padding(
              padding: const EdgeInsets.only(top: Space.s),
              child: Text(
                CalendarHe.closed,
                style: AppText.secondary.copyWith(color: p.muted),
              ),
            ),
        ],
      ),
    );
  }
}

class _TimeButton extends StatelessWidget {
  const _TimeButton({required this.text, required this.onTap});
  final String text;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => OutlinedButton(
    style: OutlinedButton.styleFrom(
      minimumSize: const Size(64, 36),
      padding: const EdgeInsets.symmetric(horizontal: Space.s),
    ),
    onPressed: onTap,
    child: Text(text, textDirection: TextDirection.ltr),
  );
}

// "הגדרות יומן": on/off, the public link (share / new link), working hours per
// weekday, meeting length / break / notice / how far ahead, notifications
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

  /// One range per day here (the server allows more; editing collapses them).
  Future<void> _editDay(int day, {required bool start}) async {
    final h = _hours[day];
    final from = h.ranges.isEmpty ? '09:00' : h.ranges.first.start;
    final to = h.ranges.isEmpty ? '17:00' : h.ranges.last.end;
    final picked = await _pickTime(start ? from : to);
    if (picked == null || !mounted) return;
    final next = start ? TimeRangeHm(picked, to) : TimeRangeHm(from, picked);
    if (next.end.compareTo(next.start) <= 0) {
      toast(context, CalendarHe.error('VALIDATION'));
      return;
    }
    setState(() => _hours[day] = DayHours(day, [next]));
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
            onStart: () => unawaited(_editDay(d, start: true)),
            onEnd: () => unawaited(_editDay(d, start: false)),
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
    required this.onStart,
    required this.onEnd,
  });

  final String label;
  final DayHours hours;
  final ValueChanged<bool> onToggle;
  final VoidCallback onStart;
  final VoidCallback onEnd;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final open = hours.open;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        children: [
          SizedBox(width: 64, child: Text(label, style: AppText.body)),
          Switch.adaptive(value: open, onChanged: onToggle),
          const SizedBox(width: Space.s),
          if (open) ...[
            _TimeButton(text: hours.ranges.first.start, onTap: onStart),
            Text(' – ', style: AppText.body.copyWith(color: p.muted)),
            _TimeButton(text: hours.ranges.last.end, onTap: onEnd),
          ] else
            Text(
              CalendarHe.closed,
              style: AppText.secondary.copyWith(color: p.muted),
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

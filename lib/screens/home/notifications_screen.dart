// Home bell → "עדכונים" (tester feedback 2026-11-18): what happened while
// you were away — quote viewed / accepted, document signed, payment received,
// document sent or not, ITA answers, bookings, collection reminders. A tap
// marks the item read and opens its screen; "סמן הכול כנקרא" clears the badge.
// Reloads when a push arrives (notificationsVersion).

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:iconsax_flutter/iconsax_flutter.dart';

import '../../api/notifications_api.dart';
import '../../router.dart' show BusinessSection, go, openBusinessSection;
import '../../ui/ds.dart';
import '../../util/labels/labels.dart' show relativeDateHe;
import '../../util/labels/notifications_he.dart';

class NotificationsScreen extends StatefulWidget {
  const NotificationsScreen({super.key, this.now});

  /// Injectable clock (tests).
  final DateTime Function()? now;

  @override
  State<NotificationsScreen> createState() => _NotificationsScreenState();
}

class _NotificationsScreenState extends State<NotificationsScreen> {
  List<AppNotification>? _items;
  String? _nextBefore;
  Object? _error;
  bool _loadingMore = false;

  @override
  void initState() {
    super.initState();
    notificationsVersion.addListener(_reload);
    unawaited(_reload());
  }

  @override
  void dispose() {
    notificationsVersion.removeListener(_reload);
    super.dispose();
  }

  Future<void> _reload() async {
    try {
      final page = await fetchNotifications();
      if (!mounted) return;
      setState(() {
        _items = page.items;
        _nextBefore = page.nextBefore;
        _error = null;
      });
    } on Object catch (e) {
      if (mounted) setState(() => _error = e);
    }
  }

  Future<void> _more() async {
    final before = _nextBefore;
    if (before == null || _loadingMore) return;
    setState(() => _loadingMore = true);
    try {
      final page = await fetchNotifications(before: before);
      if (!mounted) return;
      setState(() {
        _items = [...?_items, ...page.items];
        _nextBefore = page.nextBefore;
      });
    } on Object catch (e) {
      if (mounted) showErrorSnack(context, e);
    } finally {
      if (mounted) setState(() => _loadingMore = false);
    }
  }

  Future<void> _open(AppNotification n) async {
    if (!n.read) {
      setState(() {
        _items = [
          for (final i in _items ?? const <AppNotification>[])
            i.id == n.id ? i.asRead() : i,
        ];
      });
      unawaited(markNotificationsRead(ids: [n.id]).catchError((Object _) {}));
    }
    await go(n.route, context: context);
  }

  Future<void> _markAll() async {
    try {
      await markNotificationsRead(all: true);
      if (!mounted) return;
      setState(() {
        _items = [for (final i in _items ?? const []) i.asRead()];
      });
    } on Object catch (e) {
      if (mounted) showErrorSnack(context, e);
    }
  }

  @override
  Widget build(BuildContext context) {
    final items = _items;
    final anyUnread = items?.any((i) => !i.read) ?? false;
    return Scaffold(
      appBar: AppBar(
        title: const Text(NotificationsHe.title),
        actions: [
          if (anyUnread)
            TextButton(
              key: const Key('notifications-mark-all'),
              onPressed: () => unawaited(_markAll()),
              child: const Text(NotificationsHe.markAllRead),
            ),
          IconButton(
            key: const Key('notifications-settings'),
            tooltip: NotificationPrefsHe.gearTooltip,
            icon: const Icon(Iconsax.setting_2),
            onPressed: () =>
                unawaited(openBusinessSection(context, BusinessSection.alerts)),
          ),
        ],
      ),
      body: SafeArea(
        child: switch ((items, _error)) {
          (null, final Object e) => ErrorView(error: e, onRetry: _reload),
          (null, _) => const SkeletonList(rows: 6),
          (final List<AppNotification> list, _) when list.isEmpty =>
            const EmptyState(
              key: Key('notifications-empty'),
              icon: Iconsax.notification,
              title: NotificationsHe.empty,
              message: NotificationsHe.emptyBody,
            ),
          (final List<AppNotification> list, _) => RefreshIndicator(
            onRefresh: _reload,
            child: ListView.separated(
              key: const Key('notifications-list'),
              padding: const EdgeInsets.symmetric(vertical: Space.s),
              itemCount: list.length + (_nextBefore == null ? 0 : 1),
              separatorBuilder: (_, _) => const Divider(height: 1),
              itemBuilder: (context, i) {
                if (i == list.length) {
                  return Center(
                    child: TextButton(
                      key: const Key('notifications-more'),
                      onPressed: _loadingMore ? null : () => unawaited(_more()),
                      child: const Text(NotificationsHe.loadMore),
                    ),
                  );
                }
                return _NotificationTile(
                  item: list[i],
                  now: widget.now?.call() ?? DateTime.now(),
                  onTap: () => unawaited(_open(list[i])),
                );
              },
            ),
          ),
        },
      ),
    );
  }
}

class _NotificationTile extends StatelessWidget {
  const _NotificationTile({
    required this.item,
    required this.now,
    required this.onTap,
  });

  final AppNotification item;
  final DateTime now;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final (icon, color) = notificationIcon(item.kind, p);
    final at = item.occurredAt;
    final sameDay =
        at.year == now.year && at.month == now.month && at.day == now.day;
    final hhmm =
        '${at.hour.toString().padLeft(2, '0')}:${at.minute.toString().padLeft(2, '0')}';
    final date =
        '${at.year}-${at.month.toString().padLeft(2, '0')}-${at.day.toString().padLeft(2, '0')}';
    final when = sameDay ? hhmm : '${relativeDateHe(date, now: now)} · $hhmm';
    return Semantics(
      button: true,
      label: item.read
          ? item.title
          : '${NotificationsHe.unreadDot}: ${item.title}',
      excludeSemantics: true,
      child: InkWell(
        key: Key('notification-${item.id}'),
        onTap: onTap,
        child: Container(
          color: item.read ? null : p.surface,
          padding: const EdgeInsets.symmetric(
            horizontal: Space.page,
            vertical: Space.m,
          ),
          child: Row(
            children: [
              CircleAvatar(
                radius: 20,
                backgroundColor: color.withValues(alpha: .14),
                child: Icon(icon, color: color, size: 20),
              ),
              const SizedBox(width: Space.m),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      item.title,
                      style: AppText.body.copyWith(
                        fontWeight: item.read
                            ? FontWeight.w400
                            : FontWeight.w700,
                      ),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 2),
                    Text(
                      when,
                      style: AppText.secondary.copyWith(color: p.muted),
                    ),
                  ],
                ),
              ),
              if (!item.read)
                Container(
                  key: Key('notification-unread-${item.id}'),
                  width: 9,
                  height: 9,
                  decoration: BoxDecoration(
                    color: p.info,
                    shape: BoxShape.circle,
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Icon + tone per server kind (unknown kinds get a neutral bell).
(IconData, Color) notificationIcon(String kind, AppPalette p) => switch (kind) {
  'QUOTE_ACCEPTED' ||
  'SIGN_REQUEST_COMPLETED' ||
  'ITA_ALLOCATION_APPROVED' => (Iconsax.tick_circle, p.ok),
  'QUOTE_VIEWED' || 'SIGN_REQUEST_VIEWED' => (Iconsax.eye, p.info),
  'PAYMENT_RECEIVED' => (Iconsax.money_recive, p.ok),
  'DOCUMENT_SENT' => (Iconsax.send_2, p.info),
  'DOCUMENT_SEND_FAILED' ||
  'ITA_ALLOCATION_REJECTED' => (Iconsax.danger, p.danger),
  'BOOKING_NEW' => (Iconsax.calendar_1, p.info),
  'COLLECTION_REMINDERS_READY' ||
  'COLLECTION_REMINDERS_SENT' => (Iconsax.notification_bing, p.warn),
  _ => (Iconsax.notification, p.muted),
};

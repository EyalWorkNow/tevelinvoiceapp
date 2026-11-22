// "לקוחות חסומים" (calendar v2): clients the owner blocked from a booking —
// they cannot book from the public page (and are never told). One row each
// with "ביטול חסימה".

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:iconsax_flutter/iconsax_flutter.dart';

import '../../ui/app_page_route.dart';
import '../../ui/ds.dart';
import '../../util/labels/calendar_he.dart';
import '../../util/phone.dart';
import '../business/business_template.dart';
import '../document/dialogs.dart' show toast;
import 'calendar_api.dart';

Future<void> openBlockedContacts(BuildContext context) =>
    Navigator.of(context).push(
      AppPageRoute<void>(
        builder: (_) => const BlockedContactsScreen(),
        settings: const RouteSettings(name: '/calendar/blocked'),
      ),
    );

class BlockedContactsScreen extends StatefulWidget {
  const BlockedContactsScreen({super.key});

  @override
  State<BlockedContactsScreen> createState() => _BlockedContactsScreenState();
}

class _BlockedContactsScreenState extends State<BlockedContactsScreen> {
  List<BlockedContact>? _contacts;
  Object? _error;
  final Set<String> _busy = {};

  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  Future<void> _load() async {
    try {
      final c = await fetchBlockedContacts();
      if (mounted) {
        setState(() {
          _contacts = c;
          _error = null;
        });
      }
    } on Object catch (e) {
      if (mounted) setState(() => _error = e);
    }
  }

  Future<void> _unblock(BlockedContact c) async {
    setState(() => _busy.add(c.id));
    try {
      await unblockContact(c.id);
      if (!mounted) return;
      setState(() => _contacts = [..._contacts!]..remove(c));
      toast(context, CalendarHe.unblocked);
    } on Object catch (e) {
      if (mounted) showErrorSnack(context, e);
    } finally {
      if (mounted) setState(() => _busy.remove(c.id));
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final contacts = _contacts;
    return BusinessPage(
      title: CalendarHe.blockedClients,
      onRefresh: _load,
      children: [
        if (contacts == null && _error != null)
          ErrorView(error: _error!, onRetry: () => unawaited(_load()))
        else if (contacts == null)
          const Padding(
            padding: EdgeInsets.only(top: Space.xl),
            child: Center(child: CircularProgressIndicator.adaptive()),
          )
        else if (contacts.isEmpty)
          const EmptyState(
            icon: Iconsax.user_tick,
            title: CalendarHe.noBlockedClients,
            message: CalendarHe.blockedClientsHint,
          )
        else
          for (final c in contacts)
            ListTile(
              key: Key('blocked-${c.id}'),
              contentPadding: EdgeInsets.zero,
              title: Text(c.name.isEmpty ? c.phone : c.name),
              subtitle: Text(
                [
                  if (c.phone.isNotEmpty) formatPhoneHe(c.phone),
                  if (c.email.isNotEmpty) c.email,
                ].join(' · '),
                textDirection: TextDirection.ltr,
                textAlign: TextAlign.end,
                style: AppText.secondary.copyWith(color: p.muted),
              ),
              trailing: TextButton(
                key: Key('blocked-unblock-${c.id}'),
                onPressed: _busy.contains(c.id)
                    ? null
                    : () => unawaited(_unblock(c)),
                child: const Text(CalendarHe.unblock),
              ),
            ),
      ],
    );
  }
}

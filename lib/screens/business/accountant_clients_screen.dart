// Feature 5 · an accountant without client businesses yet: "הלקוחות שלי"
// (empty: "＋ הוספת לקוח ראשון") + pending access requests + settings. Never
// touches session.business (null here): no documents, reports or billing until
// an owner approves. Pull to refresh; once a business exists → the normal
// sign-in routing (home).

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:iconsax_flutter/iconsax_flutter.dart';

import '../../api/accountant_api.dart';
import '../../state/accountant_store.dart';
import '../../state/session.dart';
import '../../ui/ds.dart';
import '../../util/labels/labels.dart';
import '../auth/auth_flow.dart' show routeSignedIn;
import 'account_page.dart';
import 'sheets/accountant_sheets.dart';
import 'sheets/s14_switch.dart' show RequestTile;

class AccountantClientsScreen extends StatefulWidget {
  const AccountantClientsScreen({super.key});

  @override
  State<AccountantClientsScreen> createState() =>
      _AccountantClientsScreenState();
}

class _AccountantClientsScreenState extends State<AccountantClientsScreen> {
  @override
  void initState() {
    super.initState();
    unawaited(accountantStore.load());
  }

  Future<void> _refresh() async {
    await accountantStore.load();
    try {
      await session.refreshAccount();
    } on Object {
      // Offline: the list stays as it is.
    }
    // An owner approved: the client business is in the session now → home.
    if (mounted && session.businesses.any(isAccountantMembership)) {
      await routeSignedIn(context);
    }
  }

  Future<void> _add() async {
    if (!accountantStore.isAccountant) {
      final saved = await showOfficeNameSheet(context);
      if (saved == null || !mounted) return;
    }
    await showAddClientSheet(context);
  }

  void _settings() => Navigator.of(context).push<void>(
    MaterialPageRoute<void>(
      settings: const RouteSettings(name: '/gate/accountant/settings'),
      builder: (_) => const AccountPage(),
    ),
  );

  @override
  Widget build(BuildContext context) => Scaffold(
    key: const Key('accountant-clients'),
    appBar: AppBar(
      title: const Text(AccountantHe.myClients),
      actions: [
        IconButton(
          key: const Key('accountant-settings'),
          tooltip: AccountantHe.settings,
          icon: const Icon(Iconsax.setting_2),
          onPressed: _settings,
        ),
      ],
    ),
    body: SafeArea(
      child: ListenableBuilder(
        listenable: accountantStore,
        builder: (context, _) {
          final o = accountantStore.overview;
          final requests = o?.requests ?? const <AccessRequest>[];
          return RefreshIndicator(
            onRefresh: _refresh,
            child: ListView(
              padding: const EdgeInsets.all(Space.page),
              children: [
                if (o?.officeName case final office?
                    when office.trim().isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(bottom: Space.m),
                    child: Text(
                      office,
                      key: const Key('accountant-office'),
                      style: AppText.secondary.copyWith(
                        color: context.palette.muted,
                      ),
                    ),
                  ),
                if (requests.isEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: Space.xxl),
                    child: EmptyState(
                      key: const Key('accountant-empty'),
                      icon: Iconsax.briefcase,
                      title: AccountantHe.emptyTitle,
                      message: AccountantHe.emptyBody,
                      actionLabel: AccountantHe.addFirstClient,
                      onAction: session.offline ? null : _add,
                    ),
                  )
                else ...[
                  for (final r in requests) RequestTile(request: r),
                  ListTile(
                    key: const Key('accountant-add'),
                    contentPadding: EdgeInsets.zero,
                    minTileHeight: Hit.row,
                    leading: const Icon(Iconsax.user_add),
                    title: const Text(
                      AccountantHe.addClient,
                      style: AppText.body,
                    ),
                    onTap: session.offline ? null : _add,
                  ),
                ],
              ],
            ),
          );
        },
      ),
    ),
  );
}

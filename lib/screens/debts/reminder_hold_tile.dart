// "אל תשלח תזכורות ללקוח הזה" (person screen) / "השהה תזכורות אוטומטיות"
// (an open invoice). Owner / partner only (settings.business); hidden on a
// server without automatic collection reminders (0111).

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:iconsax_flutter/iconsax_flutter.dart';

import '../../api/collection_reminders_api.dart';
import '../../state/business_context.dart';
import '../../state/caps.dart';
import '../../state/session.dart';
import '../../ui/ds.dart';
import '../../util/labels/collection_he.dart';

/// Reads the hold (tests replace it).
Future<bool?> Function({String? customerId, String? documentId})
loadReminderHold = fetchReminderHold;

class ReminderHoldTile extends StatefulWidget {
  const ReminderHoldTile({super.key, this.customerId, this.documentId})
    : assert((customerId == null) != (documentId == null));

  final String? customerId;
  final String? documentId;

  @override
  State<ReminderHoldTile> createState() => _ReminderHoldTileState();
}

class _ReminderHoldTileState extends State<ReminderHoldTile> {
  bool? _onHold;
  bool _busy = false;

  bool get _allowed => businessContext.caps.can(Cap.settingsBusiness);

  @override
  void initState() {
    super.initState();
    if (_allowed) unawaited(_load());
  }

  Future<void> _load() async {
    try {
      final v = await loadReminderHold(
        customerId: widget.customerId,
        documentId: widget.documentId,
      );
      if (mounted) setState(() => _onHold = v);
    } on Object {
      // Offline / error: the row stays hidden (it is a setting, not a fact).
    }
  }

  Future<void> _set(bool on) async {
    final before = _onHold;
    setState(() {
      _onHold = on;
      _busy = true;
    });
    try {
      await saveReminderHold(
        customerId: widget.customerId,
        documentId: widget.documentId,
        onHold: on,
      );
    } on Object catch (e) {
      if (!mounted) return;
      setState(() => _onHold = before);
      showErrorSnack(context, e);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final onHold = _onHold;
    if (!_allowed || onHold == null) return const SizedBox.shrink();
    final customer = widget.customerId != null;
    final p = context.palette;
    return ListTile(
      key: Key(customer ? 'reminder-hold-customer' : 'reminder-hold-document'),
      contentPadding: customer
          ? null
          : EdgeInsets.zero, // the document screen's rows have no inset
      minTileHeight: Hit.row,
      leading: const Icon(Iconsax.notification_status),
      title: Text(
        customer ? CollectionHe.holdCustomer : CollectionHe.holdDocument,
        style: AppText.body,
      ),
      subtitle: Text(
        customer
            ? CollectionHe.holdCustomerHint
            : CollectionHe.holdDocumentHint,
        style: AppText.secondary.copyWith(color: p.muted),
      ),
      trailing: Switch.adaptive(
        key: Key(customer ? 'reminder-hold-switch' : 'reminder-pause-switch'),
        value: onHold,
        onChanged: _busy || session.offline ? null : _set,
      ),
    );
  }
}

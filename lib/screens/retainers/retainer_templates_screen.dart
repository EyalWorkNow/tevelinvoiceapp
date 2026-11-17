// The monthly invoices ("חשבוניות חודשיות"): pause / resume, end, and a price
// change that applies from next month (this month's draft is edited on
// "חשבוניות החודש"). QA 2026-11-16 C4.

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:iconsax_flutter/iconsax_flutter.dart';

import '../../ui/app_page_route.dart';
import '../../ui/ds.dart';
import '../../util/labels/retainer_he.dart';
import '../../util/money.dart';
import '../business/business_template.dart';
import '../document/dialogs.dart' show toast;
import 'retainers_api.dart';
import 'retainers_month_screen.dart' show showPricesDialog;

Future<void> openRetainerTemplates(BuildContext context) =>
    Navigator.of(context).push(
      AppPageRoute<void>(
        builder: (_) => const RetainerTemplatesScreen(),
        settings: const RouteSettings(name: '/retainers/templates'),
      ),
    );

class RetainerTemplatesScreen extends StatefulWidget {
  const RetainerTemplatesScreen({super.key});

  @override
  State<RetainerTemplatesScreen> createState() =>
      _RetainerTemplatesScreenState();
}

class _RetainerTemplatesScreenState extends State<RetainerTemplatesScreen> {
  List<RetainerTemplate>? _templates;
  Object? _error;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  Future<void> _load() async {
    try {
      final t = await fetchRetainerTemplates();
      if (!mounted) return;
      setState(() {
        _templates = t;
        _error = null;
      });
    } on Object catch (e) {
      if (mounted) setState(() => _error = e);
    }
  }

  Future<void> _patch(
    RetainerTemplate t,
    Map<String, dynamic> patch, {
    String? done,
  }) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      await updateRetainerTemplate(t.id, patch);
      if (mounted && done != null) toast(context, done);
      await _load();
    } on Object catch (e) {
      if (mounted) showErrorSnack(context, e);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _actions(RetainerTemplate t) async {
    final action = await showAppSheet<String>(
      context,
      builder: (c) => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SheetTitle(t.customerName, subtitle: RetainerHe.every(t.dayOfMonth)),
          if (t.status != 'ENDED') ...[
            ListTile(
              key: const Key('template-price'),
              leading: const Icon(Iconsax.money_change),
              title: const Text(RetainerHe.changePrice),
              onTap: () => Navigator.pop(c, 'price'),
            ),
            ListTile(
              key: const Key('template-pause'),
              leading: Icon(
                t.status == 'PAUSED' ? Iconsax.play : Iconsax.pause,
              ),
              title: Text(
                t.status == 'PAUSED' ? RetainerHe.resume : RetainerHe.pause,
              ),
              onTap: () => Navigator.pop(c, 'pause'),
            ),
            ListTile(
              key: const Key('template-end'),
              leading: Icon(Iconsax.stop_circle, color: c.palette.danger),
              title: Text(
                RetainerHe.end,
                style: TextStyle(color: c.palette.danger),
              ),
              onTap: () => Navigator.pop(c, 'end'),
            ),
          ],
        ],
      ),
    );
    if (!mounted || action == null) return;
    switch (action) {
      case 'pause':
        await _patch(t, {'status': t.status == 'PAUSED' ? 'ACTIVE' : 'PAUSED'});
      case 'end':
        final ok = await showDialog<bool>(
          context: context,
          builder: (c) => AlertDialog(
            title: const Text(RetainerHe.endConfirmTitle),
            content: const Text(RetainerHe.endConfirmBody),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(c, false),
                child: const Text(RetainerHe.cancel),
              ),
              TextButton(
                key: const Key('template-end-confirm'),
                onPressed: () => Navigator.pop(c, true),
                child: const Text(RetainerHe.end),
              ),
            ],
          ),
        );
        if (ok == true && mounted) await _patch(t, {'status': 'ENDED'});
      case 'price':
        final base = t.pendingLines ?? t.lines;
        final prices = await showPricesDialog(
          context,
          title: RetainerHe.changePrice,
          prices: [for (final l in base) l.unitPriceMinor],
        );
        if (prices == null || !mounted) return;
        await _patch(t, {
          'lines': [
            for (final (i, l) in base.indexed) l.withPrice(prices[i]).toJson(),
          ],
        }, done: RetainerHe.priceSaved);
    }
  }

  @override
  Widget build(BuildContext context) {
    final list = _templates;
    return BusinessPage(
      title: RetainerHe.templatesTitle,
      onRefresh: _load,
      children: [
        if (_error != null && list == null)
          ErrorView(error: _error!, onRetry: () => unawaited(_load()))
        else if (list == null)
          const Padding(
            padding: EdgeInsets.only(top: Space.xl),
            child: Center(child: CircularProgressIndicator.adaptive()),
          )
        else if (list.isEmpty)
          const EmptyState(
            icon: Iconsax.calendar_1,
            title: RetainerHe.templatesEmpty,
            message: RetainerHe.nothingYetBody,
          )
        else
          for (final t in list)
            BusinessRow(
              key: Key('template-${t.id}'),
              label: t.title == null
                  ? t.customerName
                  : '${t.customerName} · ${t.title}',
              value: [
                RetainerHe.every(t.dayOfMonth),
                t.lines.any((l) => l.taxRateBasisPoints > 0)
                    ? RetainerHe.netPlusVat(
                        formatMoney(t.subtotalMinor, trimZeroAgorot: true),
                      )
                    : formatMoney(t.subtotalMinor, trimZeroAgorot: true),
                RetainerHe.templateStatus(t.status),
                if (t.pendingFromPeriod != null)
                  RetainerHe.priceFrom(t.pendingFromPeriod!),
              ].join(' · '),
              icon: Iconsax.calendar_tick,
              onTap: _busy || t.status == 'ENDED'
                  ? null
                  : () => unawaited(_actions(t)),
            ),
      ],
    );
  }
}

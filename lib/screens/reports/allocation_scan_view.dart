// R7 · "מספרי הקצאה חסרים" (/reports/allocation-missing): 305/320 of the last
// 12 months that needed an allocation number and have none. Tap → D, where
// "נסה שוב" requests the number after the fact.

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:iconsax_flutter/iconsax_flutter.dart';

import '../../api/allocation_scan_api.dart';
import '../../router.dart' show openDocument;
import '../../state/session.dart';
import '../../ui/ds.dart';
import '../../util/allocation_meter.dart';
import '../home/doc_rows.dart' show docRowFor;

/// The /reports/:kind slug of the scan.
const String allocationScanKind = 'allocation-missing';

class AllocationScanView extends StatefulWidget {
  const AllocationScanView({super.key});

  @override
  State<AllocationScanView> createState() => _AllocationScanViewState();
}

class _AllocationScanViewState extends State<AllocationScanView> {
  AllocationScanResult? _result;
  Object? _error;

  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  Future<void> _load() async {
    setState(() {
      _result = null;
      _error = null;
    });
    try {
      final r = await scanMissingAllocations();
      if (mounted) setState(() => _result = r);
    } on Object catch (e) {
      if (mounted) setState(() => _error = e);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text(AllocationHe.scanTitle)),
    body: SafeArea(
      child: Column(
        children: [
          OfflineBanner(visible: session.offline),
          Expanded(child: _body(context)),
        ],
      ),
    ),
  );

  Widget _body(BuildContext context) {
    if (_error != null) return ErrorView(error: _error!, onRetry: _load);
    final r = _result;
    if (r == null) return const SkeletonList(rows: 4);
    final p = context.palette;
    return RefreshIndicator(
      onRefresh: _load,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(
          Space.page,
          Space.s,
          Space.page,
          Space.xl,
        ),
        children: [
          Text(
            AllocationHe.scanIntro,
            style: AppText.secondary.copyWith(color: p.muted),
          ),
          const SizedBox(height: Space.m),
          if (r.missing.isEmpty)
            const SizedBox(
              height: 280,
              child: EmptyState(
                key: Key('allocation-scan-empty'),
                icon: Iconsax.verify,
                title: AllocationHe.scanEmpty,
              ),
            )
          else ...[
            Text(
              AllocationHe.scanCount(r.missing.length),
              key: const Key('allocation-scan-count'),
              style: AppText.headline,
            ),
            for (final m in r.missing)
              docRowFor(
                m.document,
                key: Key('allocation-missing-${m.document.id}'),
                onTap: () => openDocument(context, m.document.id),
              ),
          ],
          if (r.partial)
            Padding(
              padding: const EdgeInsets.only(top: Space.m),
              child: Text(
                AllocationHe.scanPartial,
                key: const Key('allocation-scan-partial'),
                style: AppText.secondary.copyWith(color: p.muted),
              ),
            ),
          if (r.missing.any((m) => m.local))
            Padding(
              padding: const EdgeInsets.only(top: Space.s),
              child: Text(
                AllocationHe.scanLocal,
                style: AppText.secondary.copyWith(color: p.muted),
              ),
            ),
        ],
      ),
    );
  }
}

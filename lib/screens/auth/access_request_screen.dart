// Feature 2 · the business owner approves an accountant's access request.
// Reached from https://<host>/m/access/:token (universal link) or
// tevel://access/:token (router.dart, next to /m/invite/:token), once signed
// in: GET /mobile/access-requests/:token → who asks, three plain bullets of
// what they can do, pick a business (if several), role toggle, approve /
// decline (POST …/decide). Nothing about the owner's businesses goes to the
// accountant before the approval.

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:iconsax_flutter/iconsax_flutter.dart';

import '../../api/accountant_api.dart';
import '../../api/client.dart';
import '../../state/caps.dart' show isFullAccountantRole;
import '../../state/session.dart';
import '../../ui/ds.dart';
import '../../ui/widgets/notch_notice.dart';
import '../../util/labels/labels.dart';
import '../business/sheets/accountant_sheets.dart' show RoleToggle;

class AccessRequestScreen extends StatefulWidget {
  const AccessRequestScreen({super.key, required this.token});

  final String token;

  @override
  State<AccessRequestScreen> createState() => _AccessRequestScreenState();
}

class _AccessRequestScreenState extends State<AccessRequestScreen> {
  AccessRequestPreview? _preview;
  Object? _loadError;
  String? _businessId;
  String _role = 'ACCOUNTANT_REP';
  String? _busy;
  String? _fieldError;

  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  Future<void> _load() async {
    setState(() => _loadError = null);
    try {
      final preview = await fetchAccessRequest(widget.token);
      if (!mounted) return;
      setState(() {
        _preview = preview;
        _role = isFullAccountantRole(preview.role)
            ? 'ACCOUNTANT'
            : 'ACCOUNTANT_REP';
        if (preview.businesses.length == 1) {
          _businessId = preview.businesses.first.id;
        }
      });
    } on Object catch (e) {
      if (mounted) setState(() => _loadError = e);
    }
  }

  Future<void> _decide(bool approve) async {
    if (_busy != null) return;
    if (approve && _businessId == null) {
      setState(() => _fieldError = AccountantHe.pickBusiness);
      return;
    }
    setState(() {
      _busy = approve ? 'approve' : 'decline';
      _fieldError = null;
    });
    try {
      await decideAccessRequest(
        widget.token,
        approve: approve,
        businessId: _businessId,
        role: _role,
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showNotchNotice(
        SnackBar(
          content: Text(
            approve ? AccountantHe.approved : AccountantHe.declinedDone,
          ),
        ),
        motion: approve ? NoticeMotion.approved : NoticeMotion.sent,
      );
      Navigator.of(context).pop();
    } on ApiException catch (e) {
      if (!mounted) return;
      if (e.code == 'ACCESS_REQUEST_NOT_FOUND' || e.status == 404) {
        setState(() => _loadError = e);
      } else {
        setState(
          () => _fieldError = e.code == 'ALREADY_MEMBER'
              ? AccountantHe.alreadyMember
              : e.messageHe,
        );
      }
    } finally {
      if (mounted) setState(() => _busy = null);
    }
  }

  @override
  Widget build(BuildContext context) {
    final preview = _preview;
    return Scaffold(
      appBar: AppBar(title: const Text(AccountantHe.approveTitle)),
      body: SafeArea(
        bottom: false,
        child: _loadError != null
            ? _error(context, _loadError!)
            : preview == null
            ? const SkeletonList(rows: 4)
            : _body(context, preview),
      ),
      bottomNavigationBar:
          preview == null || _loadError != null || preview.businesses.isEmpty
          ? null
          : BottomActionArea(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (_fieldError != null)
                    Padding(
                      padding: const EdgeInsets.only(bottom: Space.s),
                      child: Semantics(
                        liveRegion: true,
                        child: Text(
                          _fieldError!,
                          key: const Key('access-error'),
                          textAlign: TextAlign.center,
                          style: AppText.body.copyWith(
                            color: context.palette.danger,
                          ),
                        ),
                      ),
                    ),
                  PrimaryButton(
                    key: const Key('access-approve'),
                    label: AccountantHe.approve,
                    loadingText: _busy == 'approve'
                        ? AccountantHe.approve
                        : null,
                    offline: session.offline,
                    onPressed: () => unawaited(_decide(true)),
                  ),
                  TextButton(
                    key: const Key('access-decline'),
                    onPressed: _busy != null || session.offline
                        ? null
                        : () => unawaited(_decide(false)),
                    child: const Text(AccountantHe.decline),
                  ),
                ],
              ),
            ),
    );
  }

  Widget _error(BuildContext context, Object e) {
    final gone =
        e is ApiException &&
        (e.status == 404 || e.code == 'ACCESS_REQUEST_NOT_FOUND');
    if (!gone) return ErrorView(error: e, onRetry: () => unawaited(_load()));
    return const EmptyState(
      key: Key('access-not-found'),
      icon: Iconsax.timer_1,
      title: AccountantHe.approveTitle,
      message: AccountantHe.notFound,
    );
  }

  Widget _body(BuildContext context, AccessRequestPreview r) {
    final p = context.palette;
    final name = r.accountantName.isEmpty
        ? r.accountantEmail
        : r.accountantName;
    final bullets = isFullAccountantRole(_role)
        ? AccountantHe.canFull
        : AccountantHe.canRep;
    return ListView(
      key: const Key('access-request'),
      padding: const EdgeInsets.all(Space.page),
      children: [
        Semantics(
          header: true,
          child: Text(AccountantHe.asks(name), style: AppText.title),
        ),
        const SizedBox(height: Space.s),
        if (r.officeName != null && r.officeName!.trim().isNotEmpty)
          Text(r.officeName!, style: AppText.body),
        if (r.accountantEmail.isNotEmpty)
          Text(
            ltrIsolate(r.accountantEmail),
            style: AppText.secondary.copyWith(color: p.muted),
          ),
        const SizedBox(height: Space.xl),
        if (r.businesses.isEmpty)
          Text(
            AccountantHe.noManagedBusiness,
            key: const Key('access-no-business'),
            style: AppText.body,
          )
        else ...[
          if (r.businesses.length > 1) ...[
            Text(AccountantHe.pickBusiness, style: AppText.headline),
            RadioGroup<String>(
              groupValue: _businessId,
              onChanged: (v) => setState(() => _businessId = v),
              child: Column(
                children: [
                  for (final b in r.businesses)
                    RadioListTile<String>(
                      key: Key('access-business-${b.id}'),
                      contentPadding: EdgeInsets.zero,
                      value: b.id,
                      title: Text(b.name, style: AppText.body),
                    ),
                ],
              ),
            ),
            const SizedBox(height: Space.l),
          ],
          Text(AccountantHe.roleLabel, style: AppText.headline),
          const SizedBox(height: Space.s),
          RoleToggle(value: _role, onChanged: (v) => setState(() => _role = v)),
          const SizedBox(height: Space.l),
          Text(AccountantHe.canDoTitle, style: AppText.headline),
          const SizedBox(height: Space.s),
          for (final b in bullets)
            Padding(
              padding: const EdgeInsets.only(bottom: Space.s),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(Iconsax.tick_circle, size: 18, color: p.ok),
                  const SizedBox(width: Space.s),
                  Expanded(child: Text(b, style: AppText.body)),
                ],
              ),
            ),
          const SizedBox(height: Space.l),
          Text(
            AccountantHe.removeAnytime,
            style: AppText.secondary.copyWith(color: p.muted),
          ),
        ],
      ],
    );
  }
}

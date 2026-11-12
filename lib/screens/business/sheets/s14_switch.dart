// S14 · החלפת עסק (SPEC-v2 §6 sheets, J12 = 2 taps). Owner: squad E.
// Search when > 7 businesses · rows: name · role tag · "פעיל" on the current.
// Switching reloads /me + profile (session.selectBusiness clears the old
// business's /me, profile and caps) and resets the stack to home.
// Search (> 7) asks the server (BE-24 GET /mobile/businesses?q=, paged);
// a server without it → the session's list filtered locally.
// "+ עסק נוסף" (BE-40) → A setup for a new business; shown only when the
// server has POST /businesses.

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../api/auth_api.dart' show searchBusinesses;
import '../../../api/client.dart';
import '../../../api/settings_api.dart' show serverHasPost;
import '../../../api/models/models.dart';
import '../../../router.dart';
import '../../../state/session.dart';
import '../../../ui/ds.dart';
import '../../auth/onboarding_screen.dart' show openNewBusiness;
import '../../../util/labels/labels.dart';
import 'package:iconsax_flutter/iconsax_flutter.dart';

/// [required] = right after sign-in with several businesses (no dismiss, no
/// reset: the sign-in flow routes on). Returns the chosen business.
Future<Business?> showSwitchBusinessSheet(
  BuildContext context, {
  bool required = false,
}) async {
  final picked = await showModalBottomSheet<Business>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    showDragHandle: !required,
    isDismissible: !required,
    enableDrag: !required,
    builder: (_) => SwitchBusinessSheet(required: required),
  );
  return picked;
}

class SwitchBusinessSheet extends StatefulWidget {
  const SwitchBusinessSheet({super.key, this.required = false});

  final bool required;

  @override
  State<SwitchBusinessSheet> createState() => _SwitchBusinessSheetState();
}

class _SwitchBusinessSheetState extends State<SwitchBusinessSheet> {
  String _query = '';
  String? _loadingId;
  Object? _error;
  Timer? _debounce;

  /// Server search results (BE-24); null = show the session's list.
  List<Business>? _remote;
  int _remoteTotal = 0;
  bool _canAdd = false;

  @override
  void initState() {
    super.initState();
    if (!widget.required) unawaited(_probeAdd());
  }

  @override
  void dispose() {
    _debounce?.cancel();
    super.dispose();
  }

  Future<void> _probeAdd() async {
    try {
      final ok = await serverHasPost('/businesses');
      if (mounted && ok) setState(() => _canAdd = true);
    } on Object {
      // Offline: no "+ עסק נוסף" this time.
    }
  }

  void _onQuery(String v) {
    setState(() => _query = v);
    _debounce?.cancel();
    if (v.trim().isEmpty) {
      setState(() => _remote = null);
      return;
    }
    _debounce = Timer(
      const Duration(milliseconds: 300),
      () => _search(v, append: false),
    );
  }

  Future<void> _search(String q, {required bool append}) async {
    try {
      final page = await searchBusinesses(
        q,
        offset: append ? (_remote?.length ?? 0) : 0,
      );
      if (!mounted || q != _query) return;
      setState(() {
        if (page == null) {
          _remote = null;
        } else {
          _remote = [...?(append ? _remote : null), ...page.businesses];
          _remoteTotal = page.total;
        }
      });
    } on ApiException {
      // Offline / transient: the local filter stays.
    }
  }

  void _addBusiness() {
    final nav = Navigator.of(context);
    nav.pop();
    unawaited(openNewBusiness(nav.context));
  }

  Future<void> _pick(Business b) async {
    if (_loadingId != null) return;
    HapticFeedback.selectionClick();
    final current =
        session.business?.businessId == b.businessId && session.me != null;
    if (current) {
      Navigator.of(context).pop(b);
      return;
    }
    setState(() {
      _loadingId = b.businessId;
      _error = null;
    });
    try {
      await session.selectBusiness(b);
    } on ApiException catch (e) {
      // Offline: the choice is stored; home shows cached data + banner.
      if (!e.isNetwork) {
        if (mounted) setState(() => _error = e);
        return;
      }
    } finally {
      if (mounted) setState(() => _loadingId = null);
    }
    if (!mounted) return;
    Navigator.of(context).pop(b);
    if (!widget.required) resetToHome();
  }

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final all = session.businesses;
    final q = _query.trim();
    final shown =
        _remote ??
        (q.isEmpty
            ? all
            : [
                for (final b in all)
                  if (b.legalName.toLowerCase().contains(q.toLowerCase())) b,
              ]);
    final current = session.business?.businessId;
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: EdgeInsets.fromLTRB(
              Space.page,
              widget.required ? Space.xl : 0,
              Space.page,
              Space.m,
            ),
            child: Semantics(
              header: true,
              child: const Text(BusinessHe.switchTitle, style: AppText.title),
            ),
          ),
          if (all.length > 7)
            Padding(
              padding: const EdgeInsets.fromLTRB(
                Space.page,
                0,
                Space.page,
                Space.s,
              ),
              child: TextField(
                key: const Key('s14-search'),
                onChanged: _onQuery,
                decoration: const InputDecoration(
                  prefixIcon: Icon(Iconsax.search_normal_1),
                  hintText: BusinessHe.searchBusiness,
                ),
              ),
            ),
          Flexible(
            child: ListView(
              shrinkWrap: true,
              padding: const EdgeInsets.symmetric(horizontal: Space.page),
              children: [
                for (final b in shown)
                  _BusinessRow(
                    business: b,
                    current: b.businessId == current,
                    loading: _loadingId == b.businessId,
                    onTap: () => _pick(b),
                  ),
                if (_remote != null && _remote!.length < _remoteTotal)
                  TextButton(
                    key: const Key('s14-more'),
                    onPressed: () => _search(_query, append: true),
                    child: const Text(BusinessHe.showMoreBusinesses),
                  ),
                if (_canAdd)
                  ListTile(
                    key: const Key('s14-add'),
                    contentPadding: EdgeInsets.zero,
                    minTileHeight: Hit.row,
                    leading: const Icon(Iconsax.shop_add),
                    title: const Text(
                      BusinessHe.addBusiness,
                      style: AppText.body,
                    ),
                    onTap: session.offline ? null : _addBusiness,
                  ),
              ],
            ),
          ),
          if (_error != null)
            Padding(
              padding: const EdgeInsets.all(Space.page),
              child: Semantics(
                liveRegion: true,
                child: Text(
                  errorTextHe(_error!),
                  style: AppText.body.copyWith(color: p.danger),
                ),
              ),
            ),
          const SizedBox(height: Space.xl),
        ],
      ),
    );
  }
}

class _BusinessRow extends StatelessWidget {
  const _BusinessRow({
    required this.business,
    required this.current,
    required this.loading,
    required this.onTap,
  });

  final Business business;
  final bool current;
  final bool loading;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final role = PresetHe.label(presetOf(business.role, const []));
    return Semantics(
      button: true,
      selected: current,
      label:
          '${business.legalName}, $role${current ? ', ${BusinessHe.active}' : ''}',
      excludeSemantics: true,
      child: InkWell(
        key: Key('s14-${business.businessId}'),
        borderRadius: BorderRadius.circular(Radii.button),
        onTap: loading ? null : onTap,
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: Hit.row),
          child: Row(
            children: [
              CircleAvatar(
                radius: 20,
                backgroundColor: p.charcoal,
                foregroundColor: p.accent,
                child: Text(
                  _initial(business.legalName),
                  style: AppText.headline,
                ),
              ),
              const SizedBox(width: Space.m),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(business.legalName, style: AppText.headline),
                    Text(
                      role,
                      style: AppText.secondary.copyWith(color: p.muted),
                    ),
                  ],
                ),
              ),
              if (loading)
                const SizedBox.square(
                  dimension: 22,
                  child: CircularProgressIndicator(strokeWidth: 2.5),
                )
              else if (current)
                Text(
                  BusinessHe.active,
                  style: AppText.secondary.copyWith(color: p.ok),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

String _initial(String name) {
  final t = name.trim();
  return t.isEmpty ? '?' : t.characters.first;
}

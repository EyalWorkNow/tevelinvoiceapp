// S2 · לקוח (SPEC-v2 §6 sheets, §4.9, §10). Owner: squad D; squad B imports
// [showCustomerSheet] from the Composer, E's review imports [showSupplierSheet].
//
// Page 1 (pick): recent circles · search · "לקוח מזדמן" · "+ לקוח חדש".
//   A tap on a customer returns it at once (auto-advance, no "המשך").
// Page 2 (form): "+ לקוח חדש" opens an empty form. Contact import is optional
// through an explicit action (permission prompt, then the native picker).
// Name · phone · e-mail · tax id (check digit) · one
//   consent switch → "שמור". customerType is derived from the tax id;
//   vatDealerStatus is never asked here (§4.9).
// The same form edits an existing customer from P2 ("פרטים ועריכה") and
// creates a supplier (supplier mode: no consent, POST /suppliers).

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart'
    show defaultTargetPlatform, TargetPlatform;

import 'package:flutter/services.dart';
import 'package:flutter_native_contact_picker/flutter_native_contact_picker.dart';
import 'package:iconsax_flutter/iconsax_flutter.dart';

import '../../../ui/widgets/notch_notice.dart';
import '../../../api/customers_api.dart';
import '../../../api/models/models.dart';
import '../../../api/suppliers_api.dart';
import '../../../state/business_context.dart';
import '../../../state/caps.dart';
import '../../../ui/ds.dart';
import '../../../ui/app_page_route.dart';
import '../../../util/labels/common_he.dart';
import '../../../util/labels/people_he.dart';
import '../confirm_discard.dart';

/// A contact from the system picker.
class PickedContact {
  const PickedContact({this.name, this.phones = const []});

  final String? name;
  final List<String> phones;
}

/// The native picker; tests replace it.
Future<PickedContact?> Function() pickContact = _nativePick;

Future<PickedContact?> _nativePick() async {
  if (defaultTargetPlatform == TargetPlatform.iOS) {
    final allowed =
        await const MethodChannel(
          'tevel/contacts_permission',
        ).invokeMethod<bool>('requestAccess') ??
        false;
    if (!allowed) {
      throw PlatformException(code: 'CONTACTS_PERMISSION_DENIED');
    }
  }
  final c = await FlutterNativeContactPicker().selectContact();
  if (c == null) return null;
  return PickedContact(name: c.fullName, phones: c.phoneNumbers ?? const []);
}

/// Returns the chosen / created customer, or null when dismissed.
/// [startOnNew]: open on page 2 (S1 "לקוח", P "+ לקוח"). [edit]: edit that
/// customer (P2 "פרטים ועריכה"; [detail] adds the BE-09 fields).
Future<Customer?> showCustomerSheet(
  BuildContext context, {
  bool startOnNew = false,
  bool recentPayments = false,
  Customer? edit,
  CustomerDetail? detail,
}) async {
  final r = await _showCounterpartyPage(
    context,
    builder: (_) => CustomerSheet(
      startOnNew: startOnNew,
      recentPayments: recentPayments,
      edit: edit,
      detail: detail,
    ),
  );
  return r is Customer ? r : null;
}

/// S2 in supplier mode (E review "ספק", P "+ ספק"; [edit]: P2 supplier
/// "פרטים ועריכה", BE-16).
Future<Supplier?> showSupplierSheet(
  BuildContext context, {
  bool startOnNew = false,
  Supplier? edit,
}) async {
  final r = await _showCounterpartyPage(
    context,
    builder: (_) => CustomerSheet(
      startOnNew: startOnNew,
      suppliers: true,
      editSupplier: edit,
    ),
  );
  return r is Supplier ? r : null;
}

Future<Object?> _showCounterpartyPage(
  BuildContext context, {
  required WidgetBuilder builder,
}) => Navigator.of(context).push<Object>(
  AppPageRoute<Object>(
    settings: const RouteSettings(name: '/people/picker'),
    builder: (context) => Scaffold(
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(17, 16, 17, 24),
          child: builder(context),
        ),
      ),
    ),
  ),
);

/// One row of page 1 (a customer or a supplier).
class _Entry {
  _Entry(
    this.value,
    this.id,
    this.name,
    this.phone,
    this.email,
    this.taxId,
    this.archived,
  );

  factory _Entry.customer(Customer c) =>
      _Entry(c, c.id, c.name, c.phone, c.email, c.taxId, c.isArchived);
  factory _Entry.supplier(Supplier s) =>
      _Entry(s, s.id, s.name, s.phone, s.email, s.taxId, s.isArchived);

  final Object value;
  final String id;
  final String name;
  final String? phone;
  final String? email;
  final String? taxId;
  final bool archived;
}

class CustomerSheet extends StatefulWidget {
  const CustomerSheet({
    super.key,
    this.startOnNew = false,
    this.recentPayments = false,
    this.suppliers = false,
    this.edit,
    this.detail,
    this.editSupplier,
  });

  /// Open directly on page 2 ("לקוח חדש", e.g. from S1 "לקוח").
  final bool startOnNew;
  final bool recentPayments;
  final bool suppliers;
  final Customer? edit;
  final CustomerDetail? detail;

  /// Edit this supplier (BE-16, [suppliers] must be true).
  final Supplier? editSupplier;

  @override
  State<CustomerSheet> createState() => _CustomerSheetState();
}

class _CustomerSheetState extends State<CustomerSheet> {
  final _formKey = GlobalKey<FormState>();
  final _search = TextEditingController();
  final _searchFocus = FocusNode();
  final _name = TextEditingController();
  final _phone = TextEditingController();
  final _email = TextEditingController();
  final _taxId = TextEditingController();
  final _contact = TextEditingController();
  final _notes = TextEditingController();
  final _street = TextEditingController();
  final _houseNumber = TextEditingController();
  final _city = TextEditingController();
  final _postal = TextEditingController();
  final _accountKey = TextEditingController();
  String? _terms;
  bool _consent = false;

  late bool _form =
      widget.startOnNew || widget.edit != null || widget.editSupplier != null;
  List<_Entry>? _entries;
  List<String> _recentIds = const [];
  List<String> _recentPaymentIds = const [];
  List<Customer> _customers = const [];
  bool _be09 = false;
  Object? _loadError;
  bool _busy = false;

  bool get _isEdit => widget.edit != null || widget.editSupplier != null;
  bool get _sup => widget.suppliers;

  @override
  void initState() {
    super.initState();
    final c = widget.edit;
    if (c != null) {
      _name.text = c.name;
      _phone.text = c.phone ?? '';
      _email.text = c.email ?? '';
      _taxId.text = c.taxId ?? '';
      _contact.text = widget.detail?.contactPerson ?? '';
      _notes.text = widget.detail?.notes ?? '';
      _terms = widget.detail?.paymentTerms;
      final a = widget.detail?.address;
      _street.text = a?.street ?? '';
      _houseNumber.text = a?.number ?? '';
      _city.text = a?.city ?? '';
      _postal.text = a?.postalCode ?? '';
      _accountKey.text = widget.detail?.accountKey ?? '';
    } else if (widget.editSupplier != null) {
      final s = widget.editSupplier!;
      _name.text = s.name;
      _phone.text = s.phone ?? '';
      _email.text = s.email ?? '';
      _taxId.text = s.taxId ?? '';
    } else {
      _load();
    }
    for (final c in [_search, _name, _phone, _taxId]) {
      c.addListener(() => setState(() {}));
    }
    _formOpened = _formSignature;
  }

  /// The form as it was when it opened (empty for a new one).
  String _formOpened = '';

  String get _formSignature => [
    for (final c in [
      _name, _phone, _email, _taxId, _contact, _notes, //
      _street, _houseNumber, _city, _postal, _accountKey,
    ])
      c.text.trim(),
    _terms,
    _consent,
  ].join('\u0000');

  bool get _formDirty => _form && _formSignature != _formOpened;

  @override
  void dispose() {
    for (final c in [
      _search, _name, _phone, _email, _taxId, _contact, _notes, //
      _street, _houseNumber, _city, _postal, _accountKey,
    ]) {
      c.dispose();
    }
    _searchFocus.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      if (_sup) {
        final cached = await readCachedSuppliers();
        if (cached != null && mounted) {
          setState(() => _entries = cached.map(_Entry.supplier).toList());
        }
        final list = await fetchSuppliers();
        if (mounted) {
          setState(() => _entries = list.map(_Entry.supplier).toList());
        }
        return;
      }
      _recentIds = await readRecentCustomerIds();
      if (widget.recentPayments) {
        _recentPaymentIds = await readRecentPaymentCustomerIds();
      }
      final cached = await readCachedCustomerList();
      if (cached != null && mounted) _setCustomers(cached.customers);
      final list = await fetchCustomerList();
      _be09 = list.be09;
      if (mounted) _setCustomers(list.customers);
    } on Object catch (e) {
      if (mounted && _entries == null) setState(() => _loadError = e);
    }
  }

  void _setCustomers(List<Customer> list) => setState(() {
    _customers = list;
    _entries = sortForPeople(
      list,
      recentIds: _recentIds,
    ).map(_Entry.customer).toList();
    _loadError = null;
  });

  // §4.4: an employee creates a supplier from an expense (expense:record).
  bool get _canCreate => _sup
      ? businessContext.can(Cap.supplierManage) ||
            businessContext.can(Cap.expenseCapture)
      : businessContext.can(Cap.docDraft);

  // ---- page 1 ---------------------------------------------------------------

  Future<void> _pick(_Entry e) async {
    HapticFeedback.selectionClick();
    if (!_sup) await rememberRecentCustomer(e.id);
    if (mounted) Navigator.of(context).pop(e.value);
  }

  Future<void> _pickWalkIn() async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      final c = await walkInCustomer(
        _customers,
        name: PeopleHe.walkIn,
        be09: _be09,
      );
      if (mounted) Navigator.of(context).pop(c);
    } on Object catch (e) {
      if (!mounted) return;
      setState(() => _busy = false);
      showErrorSnack(context, e);
    }
  }

  Future<void> _openNew() async {
    setState(() {
      _form = true;
      _formOpened = _formSignature;
    });
  }

  Future<void> _importContact() async {
    try {
      final c = await pickContact();
      if (c == null || !mounted) return; // cancelled: empty form
      setState(() {
        if ((c.name ?? '').trim().isNotEmpty) _name.text = c.name!.trim();
        final phone = preferredPhone(c.phones);
        if (phone != null) _phone.text = phone;
      });
    } on PlatformException catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showNotchNotice(
          SnackBar(
            content: Text(
              error.code == 'CONTACTS_PERMISSION_DENIED'
                  ? PeopleHe.contactsPermissionDenied
                  : PeopleHe.contactsFailed,
            ),
          ),
          motion: NoticeMotion.error,
        );
      }
    }
  }

  Future<void> _newFromContact() async {
    await _openNew();
    await _importContact();
  }

  Widget _pickPage(BuildContext context) {
    final p = context.palette;
    final entries = _entries;
    final q = _search.text;
    final recent = (_sup || entries == null)
        ? const <_Entry>[]
        : recentCircles(
            entries,
            (e) => e.id,
            _recentIds,
            eligible: (e) =>
                !e.archived && (e.value as Customer).lastDocumentAt != null,
            excluded: (e) => e.archived,
          );
    final recentPaymentEntries =
        (!widget.recentPayments || _sup || entries == null || q.isNotEmpty)
        ? const <_Entry>[]
        : recentCircles(
            entries,
            (e) => e.id,
            _recentPaymentIds,
            eligible: (e) => !e.archived,
            excluded: (e) => e.archived,
          );
    final recentPaymentIds = {
      for (final entry in recentPaymentEntries) entry.id,
    };
    final shown = entries == null
        ? const <_Entry>[]
        : [
            for (final e in entries)
              if ((q.trim().isEmpty ? !e.archived : true) &&
                  !(q.trim().isEmpty && recentPaymentIds.contains(e.id)) &&
                  personMatches(
                    q,
                    name: e.name,
                    email: e.email,
                    phone: e.phone,
                    taxId: e.taxId,
                  ))
                e,
          ].take(q.trim().isEmpty ? 30 : 50).toList();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                _sup ? PeopleHe.pickSupplierTitle : PeopleHe.pickQuestion,
                style: AppText.displayTitle,
              ),
            ),
            const DesignBackButton(),
          ],
        ),
        const SizedBox(height: 26),
        TextField(
          key: const Key('s2-search'),
          controller: _search,
          focusNode: _searchFocus,
          textInputAction: TextInputAction.search,
          decoration: const InputDecoration(
            hintText: PeopleHe.searchContacts,
            prefixIcon: Icon(Icons.search_rounded),
          ),
        ),
        if (recentPaymentEntries.isNotEmpty) ...[
          const SizedBox(height: Space.m),
          Text(
            PeopleHe.recentPaymentCustomers,
            style: AppText.body.copyWith(fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: Space.xs),
          for (final entry in recentPaymentEntries.take(3))
            PersonRow(
              key: Key('s2-recent-payment-${entry.id}'),
              name: entry.name,
              subtitle: entry.phone,
              subtitleOnLeft: true,
              onTap: () => _pick(entry),
            ),
        ],
        const SizedBox(height: 36),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (_canCreate)
              Expanded(
                child: ActionOrb(
                  key: const Key('s2-new'),
                  label: _sup
                      ? PeopleHe.newSupplierTitle
                      : PeopleHe.newCustomerTitle,
                  icon: const DesignIcon('new-customer', size: 33),
                  color: DesignTokens.lavender,
                  onPressed: _openNew,
                ),
              ),
            Expanded(
              child: ActionOrb(
                label: PeopleHe.existingCustomer,
                icon: const DesignIcon('existing-customer', size: 33),
                color: DesignTokens.yellow,
                onPressed: _searchFocus.requestFocus,
              ),
            ),
            if (!_sup && _canCreate && q.isEmpty)
              Expanded(
                child: ActionOrb(
                  key: const Key('s2-walkin'),
                  label: PeopleHe.walkIn,
                  icon: const DesignIcon('walk-in'),
                  color: DesignTokens.green,
                  onPressed: _busy ? null : _pickWalkIn,
                ),
              ),
          ],
        ),
        if (!_sup && _canCreate && q.isEmpty) ...[
          const SizedBox(height: Space.s),
          TextButton.icon(
            onPressed: _busy ? null : _newFromContact,
            icon: const Icon(Icons.contacts_outlined),
            label: const Text(PeopleHe.importContactAction),
          ),
        ],
        if (!_sup && _canCreate && q.isEmpty) ...[
          const SizedBox(height: 12),
          Text(
            PeopleHe.walkInHint,
            textAlign: TextAlign.center,
            style: AppText.secondary.copyWith(fontSize: 12, color: p.muted),
          ),
        ],
        const SizedBox(height: 28),
        if (!widget.recentPayments && q.isEmpty && recent.length >= 2) ...[
          Text(
            PeopleHe.mostActive,
            style: AppText.body.copyWith(fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 12),
          for (final e in recent.take(2))
            PersonRow(
              key: Key('s2-recent-${e.id}'),
              name: e.name,
              subtitle: (e.phone != null && e.phone!.isNotEmpty)
                  ? e.phone
                  : null,
              subtitleOnLeft: true,
              onTap: () => _pick(e),
            ),
          const SizedBox(height: 20),
        ],
        Text(
          PeopleHe.yourContacts,
          style: AppText.body.copyWith(fontWeight: FontWeight.w600),
        ),
        const SizedBox(height: 12),
        if (entries == null && _loadError == null) const SkeletonList(rows: 4),
        if (entries == null && _loadError != null)
          ErrorView(
            error: _loadError!,
            onRetry: () {
              setState(() => _loadError = null);
              _load();
            },
          ),
        if (entries != null && shown.isEmpty && recentPaymentEntries.isEmpty)
          Padding(
            padding: const EdgeInsets.all(Space.l),
            child: Text(
              q.isEmpty ? PeopleHe.emptyCustomers : PeopleHe.noMatches,
              textAlign: TextAlign.center,
              style: AppText.body.copyWith(color: p.muted),
            ),
          ),
        for (final e
            in (!widget.recentPayments && q.isEmpty && recent.length >= 2
                ? shown.where((x) => !recent.take(2).any((a) => a.id == x.id))
                : shown))
          PersonRow(
            key: Key('s2-row-${e.id}'),
            name: e.name,
            subtitle: (e.phone != null && e.phone!.isNotEmpty) ? e.phone : null,
            subtitleOnLeft: true,
            badge: e.archived ? PeopleHe.archivedBadge : null,
            onTap: () => _pick(e),
          ),
      ],
    );
  }

  // ---- page 2 ---------------------------------------------------------------

  Customer? get _duplicate => _isEdit || _sup
      ? null
      : findDuplicateCustomer(
          _customers,
          name: _name.text,
          phone: _phone.text,
          taxId: _taxId.text,
        );

  String? _clean(TextEditingController c) {
    final t = c.text.trim();
    return t.isEmpty ? null : t;
  }

  Future<void> _save() async {
    if (_busy || !_formKey.currentState!.validate()) {
      HapticFeedback.heavyImpact();
      return;
    }
    FocusScope.of(context).unfocus();
    final name = _name.text.trim();
    final phone = normalizePhoneInput(_phone.text);
    final email = _clean(_email);
    final taxId = _clean(_taxId);
    setState(() => _busy = true);
    try {
      final Object saved;
      if (_sup && widget.editSupplier != null) {
        final old = widget.editSupplier!;
        await updateSupplier(old.id, {
          if (name != old.name) 'name': name,
          if (phone != old.phone) 'phone': phone,
          if (email != old.email) 'email': email,
          if (taxId != old.taxId) 'taxId': taxId,
        });
        saved = Supplier(
          id: old.id,
          name: name,
          phone: phone,
          email: email,
          taxId: taxId,
          archivedAt: old.archivedAt,
        );
      } else if (_sup) {
        saved = await createSupplier(
          name: name,
          taxId: taxId,
          phone: phone,
          email: email,
        );
      } else if (_isEdit) {
        final old = widget.edit!;
        final type = customerTypeFor(taxId);
        final d = widget.detail;
        await updateCustomer(old.id, {
          if (name != old.name) 'name': name,
          if (phone != old.phone) 'phone': phone,
          if (email != old.email) 'email': email,
          if (taxId != old.taxId) 'taxId': taxId,
          if (type != (old.customerType ?? 'INDIVIDUAL')) 'customerType': type,
          if (d != null && d.fromBe09) ...{
            if (_clean(_contact) != d.contactPerson)
              'contactPerson': _clean(_contact),
            if (_clean(_notes) != d.notes) 'notes': _clean(_notes),
            if (_terms != d.paymentTerms) 'paymentTerms': _terms,
            if (_addressChanged(d)) 'address': _addressValue?.toJson(),
            if (_showAccountKey && _clean(_accountKey) != d.accountKey)
              'accountKey': _clean(_accountKey),
          },
        });
        var consent = old.consentGranted;
        if (_consent && consent != true) {
          await grantConsent(old.id);
          consent = true;
        }
        saved = Customer(
          id: old.id,
          name: name,
          phone: phone,
          email: email,
          taxId: taxId,
          customerType: type,
          archivedAt: old.archivedAt,
          vatDealerStatus: old.vatDealerStatus,
          balanceMinor: old.balanceMinor,
          lastDocumentAt: old.lastDocumentAt,
          isWalkIn: old.isWalkIn,
          consentGranted: consent,
        );
      } else {
        final created = await createCustomer(
          name: name,
          phone: phone,
          email: email,
          taxId: taxId,
        );
        await rememberRecentCustomer(created.id);
        var result = created;
        if (_consent) {
          try {
            await grantConsent(created.id);
            result = Customer(
              id: created.id,
              name: created.name,
              phone: created.phone,
              email: created.email,
              taxId: created.taxId,
              customerType: created.customerType,
              consentGranted: true,
            );
          } on Object {
            // The customer exists; S6 asks again on CONSENT_REQUIRED (AT-31).
          }
        }
        saved = result;
      }
      HapticFeedback.mediumImpact();
      if (mounted) Navigator.of(context).pop(saved);
    } on Object catch (e) {
      HapticFeedback.heavyImpact();
      if (mounted) {
        setState(() => _busy = false);
        showErrorSnack(context, e);
      }
    }
  }

  /// The address typed in the form, or null when every part is empty.
  CustomerAddress? get _addressValue {
    final a = CustomerAddress(
      street: _street.text,
      number: _houseNumber.text,
      city: _city.text,
      postalCode: _clean(_postal),
    );
    return a.isEmpty ? null : a;
  }

  bool _addressChanged(CustomerDetail d) => _addressValue != d.address;

  /// BE-04 `customer:accountKey` (the accountant's field).
  bool get _showAccountKey => businessContext.can(Cap.customerAccountKey);

  /// Consent switch in edit mode: only while the server says it was not given.
  bool get _askConsentOnEdit =>
      widget.edit != null &&
      (widget.detail?.fromBe09 ?? false) &&
      widget.edit!.consentGranted != true;

  Widget _formPage(BuildContext context) {
    final p = context.palette;
    final dup = _duplicate;
    final be09 = widget.detail?.fromBe09 ?? false;
    return Form(
      key: _formKey,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: SheetTitle(
                  _isEdit
                      ? PeopleHe.editTitle
                      : (_sup
                            ? PeopleHe.newSupplierTitle
                            : PeopleHe.newCustomerTitle),
                ),
              ),
              DesignBackButton(onPressed: _backFromForm),
            ],
          ),
          const SizedBox(height: Space.l),
          if (!_isEdit)
            Align(
              alignment: AlignmentDirectional.centerStart,
              child: OutlinedButton.icon(
                key: const Key('s2-import-contact'),
                onPressed: _busy ? null : _importContact,
                icon: const Icon(Iconsax.user_search),
                label: const Text(PeopleHe.importContactAction),
              ),
            ),
          if (!_isEdit) const SizedBox(height: Space.m),
          TextFormField(
            key: const Key('s2-name'),
            controller: _name,
            autofocus: !_isEdit && _name.text.isEmpty,
            enabled: !_busy,
            textInputAction: TextInputAction.next,
            maxLength: 200,
            decoration: const InputDecoration(
              labelText: PeopleHe.name,
              prefixIcon: Icon(Icons.person_outline_rounded),
              counterText: '',
            ),
            validator: (v) =>
                (v ?? '').trim().isEmpty ? PeopleHe.nameRequired : null,
          ),
          const SizedBox(height: Space.m),
          _ltr(
            _phone,
            PeopleHe.phone,
            TextInputType.phone,
            's2-phone',
            Icons.phone_outlined,
            (v) => (v ?? '').trim().isEmpty || isValidPhoneInput(v!)
                ? null
                : PeopleHe.phoneInvalid,
          ),
          const SizedBox(height: Space.m),
          _ltr(
            _email,
            PeopleHe.email,
            TextInputType.emailAddress,
            's2-email',
            Icons.alternate_email_rounded,
            (v) => (v ?? '').trim().isEmpty || isValidEmail(v!)
                ? null
                : PeopleHe.emailInvalid,
          ),
          const SizedBox(height: Space.m),
          _ltr(
            _taxId,
            PeopleHe.taxId,
            TextInputType.number,
            's2-taxid',
            Icons.badge_outlined,
            (v) => (v ?? '').trim().isEmpty || isValidIsraeliId(v!.trim())
                ? null
                : PeopleHe.taxIdInvalid,
          ),
          if (be09) ...[
            const SizedBox(height: Space.m),
            TextFormField(
              controller: _contact,
              enabled: !_busy,
              decoration: const InputDecoration(
                labelText: PeopleHe.contactPerson,
                prefixIcon: Icon(Icons.contact_phone_outlined),
              ),
            ),
            const SizedBox(height: Space.l),
            Text(
              PeopleHe.paymentTerms,
              style: AppText.secondary.copyWith(color: p.muted),
            ),
            const SizedBox(height: Space.s),
            ChipRow<String>(
              padding: EdgeInsets.zero,
              options: [
                for (final e in PeopleHe.paymentTermsLabels.entries)
                  ChipOption(e.key, e.value, icon: Icons.schedule_outlined),
              ],
              selected: _terms,
              onSelected: (v) => setState(() => _terms = v),
            ),
            const SizedBox(height: Space.m),
            TextFormField(
              controller: _notes,
              enabled: !_busy,
              maxLines: 3,
              minLines: 1,
              decoration: const InputDecoration(
                labelText: PeopleHe.notes,
                prefixIcon: Icon(Icons.notes_rounded),
              ),
            ),
            const SizedBox(height: Space.l),
            Text(
              PeopleHe.address,
              style: AppText.secondary.copyWith(color: p.muted),
            ),
            Row(
              children: [
                Expanded(
                  flex: 3,
                  child: TextFormField(
                    key: const Key('s2-street'),
                    controller: _street,
                    enabled: !_busy,
                    decoration: const InputDecoration(
                      labelText: PeopleHe.street,
                      prefixIcon: Icon(Icons.signpost_outlined),
                    ),
                  ),
                ),
                const SizedBox(width: Space.s),
                Expanded(
                  child: TextFormField(
                    key: const Key('s2-house'),
                    controller: _houseNumber,
                    enabled: !_busy,
                    decoration: const InputDecoration(
                      labelText: PeopleHe.houseNumber,
                      prefixIcon: Icon(Icons.home_outlined),
                    ),
                  ),
                ),
              ],
            ),
            Row(
              children: [
                Expanded(
                  flex: 3,
                  child: TextFormField(
                    key: const Key('s2-city'),
                    controller: _city,
                    enabled: !_busy,
                    decoration: const InputDecoration(
                      labelText: PeopleHe.city,
                      prefixIcon: Icon(Icons.location_city_outlined),
                    ),
                    validator: (v) =>
                        _addressValue != null && (v ?? '').trim().isEmpty
                        ? PeopleHe.cityRequired
                        : null,
                  ),
                ),
                const SizedBox(width: Space.s),
                Expanded(
                  child: TextFormField(
                    key: const Key('s2-postal'),
                    controller: _postal,
                    enabled: !_busy,
                    keyboardType: TextInputType.number,
                    textDirection: TextDirection.ltr,
                    decoration: const InputDecoration(
                      labelText: PeopleHe.postalCode,
                      prefixIcon: Icon(Icons.markunread_mailbox_outlined),
                    ),
                  ),
                ),
              ],
            ),
            if (_showAccountKey) ...[
              const SizedBox(height: Space.m),
              TextFormField(
                key: const Key('s2-accountkey'),
                controller: _accountKey,
                enabled: !_busy,
                textDirection: TextDirection.ltr,
                decoration: const InputDecoration(
                  labelText: PeopleHe.accountKey,
                  prefixIcon: Icon(Icons.key_outlined),
                ),
              ),
            ],
          ],
          if (!_sup && (!_isEdit || _askConsentOnEdit)) ...[
            const SizedBox(height: Space.s),
            SwitchListTile.adaptive(
              key: const Key('s2-consent'),
              contentPadding: EdgeInsets.zero,
              secondary: const Icon(Icons.verified_user_outlined),
              value: _consent,
              onChanged: _busy ? null : (v) => setState(() => _consent = v),
              title: const Text(PeopleHe.consentSwitch, style: AppText.body),
              subtitle: Text(
                PeopleHe.consentHint,
                style: AppText.secondary.copyWith(color: p.muted),
              ),
            ),
          ],
          if (dup != null) ...[
            const SizedBox(height: Space.s),
            AppCard(
              key: const Key('s2-duplicate'),
              color: p.tint(p.warn),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      PeopleHe.alreadyExists(dup.name),
                      style: AppText.body,
                    ),
                  ),
                  TextButton(
                    onPressed: () => Navigator.of(context).pop(dup),
                    child: const Text(PeopleHe.useExisting),
                  ),
                ],
              ),
            ),
          ],
          if (_isEdit) ...[
            const SizedBox(height: Space.s),
            Text(
              PeopleHe.editNote,
              textAlign: TextAlign.center,
              style: AppText.secondary.copyWith(color: p.muted),
            ),
          ],
          const SizedBox(height: Space.l),
          PrimaryButton(
            key: const Key('s2-save'),
            label: CommonHe.save,
            loadingText: _busy ? PeopleHe.saving : null,
            offline: businessContext.offline,
            onPressed: _save,
          ),
        ],
      ),
    );
  }

  Widget _ltr(
    TextEditingController c,
    String label,
    TextInputType keyboard,
    String key,
    IconData icon,
    FormFieldValidator<String> validator,
  ) {
    return TextFormField(
      key: Key(key),
      controller: c,
      enabled: !_busy,
      keyboardType: keyboard,
      textDirection: TextDirection.ltr,
      textAlign: TextAlign.right,
      autocorrect: false,
      textInputAction: TextInputAction.next,
      decoration: InputDecoration(labelText: label, prefixIcon: Icon(icon)),
      validator: validator,
    );
  }

  /// Back from the form: "לצאת בלי לשמור?" when something was typed (06·9),
  /// then page 1 (opened from it) or close.
  Future<void> _backFromForm() async {
    if (_busy) return;
    if (_formDirty && !await confirmDiscardChanges(context)) return;
    if (!mounted) return;
    if (!widget.startOnNew && !_isEdit) {
      FocusScope.of(context).unfocus();
      setState(() => _form = false);
    } else {
      Navigator.of(context).pop();
    }
  }

  @override
  Widget build(BuildContext context) => PopScope<Object>(
    canPop: !_form,
    onPopInvokedWithResult: (didPop, result) {
      if (!didPop) unawaited(_backFromForm());
    },
    child: _form ? _formPage(context) : _pickPage(context),
  );
}

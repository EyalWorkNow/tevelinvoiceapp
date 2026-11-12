// E · הוצאות (review + list) (SPEC-v2 §6.E). Owner: squad D.
// Route: /expenses?id=   Capture stays in expense_capture_screen.dart.
//
// Review: one card at a time ("3 מתוך 7"), oldest first; ?id= opens on that
// expense. ⋯ "דחה" (expense.approve) → one-field dialog "למה?". OCR runs
// once per expense on this device (remembered across opens), after a one-time
// consent, when nothing was read (≤20 s, then manual entry).
// List ("כל ההוצאות"): search + "הכל" / "שלי". With BE-44 the rows come from
// GET /expenses?q=&mine=1 and an approver can open an approved expense to
// edit it ("שמור" → PATCH /expenses/:id) or ⋯ "מחק" it (DELETE). Without
// BE-44 the list is the inbox, filtered on the device; members without
// expense.approve see only what they captured on this device.

import 'dart:async';

import 'package:flutter/material.dart';

import 'package:flutter/services.dart';

import '../../ui/widgets/notch_notice.dart';
import '../../api/client.dart';
import '../../api/expenses_api.dart';
import '../../api/models/models.dart';
import '../../router.dart';
import '../../state/business_context.dart';
import '../../state/cache.dart';
import '../../state/caps.dart';
import '../../ui/ds.dart';
import '../../util/labels/common_he.dart';
import '../../util/labels/people_he.dart';
import 'expense_review_card.dart';
import 'package:iconsax_flutter/iconsax_flutter.dart';

/// Automatic receipt reading (QA 3.5): consent + once-per-expense memory.
abstract final class ExpenseOcrHe {
  static const consentTitle = 'קריאה אוטומטית של הקבלה';
  static const consentBody =
      'כדי למלא את פרטי ההוצאה בשבילך, התמונה של הקבלה תישלח לעיבוד בשירות '
      'בינה מלאכותית חיצוני (Anthropic Claude). אפשר לוותר ולהזין את הפרטים ידנית.';
  static const consentAllow = 'אישור';
  static const consentManual = 'הזנה ידנית';
}

/// Device memory: OCR consent (user data) and the expenses already sent to
/// OCR, so a failed read is not re-run each time the screen opens.
const _ocrConsentKey = 'expense_ocr_consent';
const _ocrTriedKey = 'expense_ocr_tried';

Future<Set<String>> _ocrTried() async {
  try {
    final v = await AppCache.read(_ocrTriedKey);
    return v is List ? {for (final e in v) '$e'} : <String>{};
  } on Object {
    return <String>{};
  }
}

Future<void> _rememberOcrTried(String id) async {
  final ids = [
    id,
    ...(await _ocrTried()).where((e) => e != id),
  ].take(200).toList();
  try {
    await AppCache.write(_ocrTriedKey, ids);
  } on Object {
    // best effort
  }
}

class ExpensesScreen extends StatefulWidget {
  const ExpensesScreen({
    super.key,
    this.expenseId,
    this.pollEvery = const Duration(seconds: 2),
  });

  final String? expenseId;

  /// Inbox refresh while a card is still processing (tests shorten it).
  final Duration pollEvery;

  /// How long OCR may take before the card switches to manual entry.
  static const Duration readTimeout = Duration(seconds: 20);

  @override
  State<ExpensesScreen> createState() => _ExpensesScreenState();
}

class _ExpensesScreenState extends State<ExpensesScreen> {
  List<ExpenseRow>? _rows;
  List<ExpenseCategory> _categories = const [];
  Set<String> _mine = const {};
  List<String> _queue = const [];
  int _done = 0;
  bool _list = false;
  bool _mineOnly = false;
  Object? _error;
  bool _offline = false;
  final Set<String> _extracted = {};

  /// "הזנה ידנית" in the consent dialog: not asked again on this screen.
  bool _ocrDeclined = false;
  String? _reading;
  Timer? _poll;
  DateTime? _pollUntil;
  final _query = TextEditingController();
  Timer? _searchDebounce;

  /// BE-44: null = not asked yet, false = the server has no GET /expenses.
  bool? _be44;
  List<ExpenseRow>? _serverRows;

  /// An approved expense open for editing (BE-44).
  ExpenseRow? _editing;

  Caps get _caps => businessContext.caps;
  bool get _approver => _caps.can(Cap.expenseApprove);

  @override
  void initState() {
    super.initState();
    _load(initial: true);
  }

  @override
  void dispose() {
    _poll?.cancel();
    _searchDebounce?.cancel();
    _query.dispose();
    super.dispose();
  }

  /// GET /expenses (BE-44) for the list; a server without it → inbox rows.
  Future<void> _loadList() async {
    if (_be44 == false) return;
    try {
      final page = await fetchExpenses(
        q: _query.text,
        mine: _mineOnly || !_approver,
      );
      if (!mounted) return;
      setState(() {
        _be44 = page != null;
        _serverRows = page?.expenses;
      });
    } on Object catch (e) {
      if (mounted) showErrorSnack(context, e);
    }
  }

  void _toggleList() {
    setState(() {
      _list = _editing != null || !_list;
      _editing = null;
    });
    if (_list) _loadList();
  }

  void _onQuery(String _) {
    setState(() {});
    if (_be44 != true) return;
    _searchDebounce?.cancel();
    _searchDebounce = Timer(const Duration(milliseconds: 300), _loadList);
  }

  Future<void> _delete() async {
    final r = _editing;
    if (r == null) return;
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        content: const Text(ExpenseHe.deleteConfirm),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text(CommonHe.cancel),
          ),
          TextButton(
            key: const Key('expense-delete-confirm'),
            onPressed: () => Navigator.pop(context, true),
            style: TextButton.styleFrom(
              foregroundColor: context.palette.danger,
            ),
            child: const Text(ExpenseHe.delete),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    try {
      await deleteExpense(r.id);
      HapticFeedback.mediumImpact();
      _closeEdit(ExpenseHe.deleted);
    } on Object catch (e) {
      if (mounted) showErrorSnack(context, e);
    }
  }

  void _closeEdit(String? message) {
    if (!mounted) return;
    setState(() => _editing = null);
    if (message != null) {
      ScaffoldMessenger.of(context)
        ..hideCurrentNotchNotice()
        ..showNotchNotice(SnackBar(content: Text(message)));
    }
    unawaited(_load());
    unawaited(_loadList());
  }

  /// True when the inbox was read (false: kept the rows on screen).
  Future<bool> _load({bool initial = false}) async {
    try {
      final rowsF = fetchExpenseInbox();
      final catsF = fetchExpenseCategories().catchError(
        (Object _) => const <ExpenseCategory>[],
      );
      final mine = await readMyExpenseIds();
      final rows = await rowsF;
      final cats = await catsF;
      if (!mounted) return false;
      setState(() {
        _rows = rows;
        _categories = cats;
        _mine = mine;
        _error = null;
        _offline = false;
        if (initial) _queue = _initialQueue(rows);
      });
      _afterChange();
      return true;
    } on Object catch (e) {
      if (!mounted) return false;
      setState(() {
        if (_rows == null) _error = e;
        _offline = e is ApiException && e.isNetwork;
      });
      return false;
    }
  }

  List<String> _initialQueue(List<ExpenseRow> rows) {
    final ids = [
      for (final r in expenseReviewQueue(
        rows,
        approver: _approver,
        mine: _mine,
        userId: businessContext.me?.userId,
      ))
        r.id,
    ];
    final first = widget.expenseId;
    if (first != null) {
      ids.remove(first);
      ids.insert(0, first);
    }
    return ids;
  }

  ExpenseRow? _row(String id) {
    for (final r in _rows ?? const <ExpenseRow>[]) {
      if (r.id == id) return r;
    }
    return null;
  }

  ExpenseRow? get _current => _queue.isEmpty ? null : _row(_queue.first);

  /// Poll while the current card is processing; run OCR once when nothing was read.
  void _afterChange() {
    final r = _current;
    if (r == null) return;
    if (r.isProcessing) {
      _pollUntil ??= DateTime.now().add(ExpensesScreen.readTimeout);
      _poll?.cancel();
      if (DateTime.now().isBefore(_pollUntil!)) {
        _poll = Timer(widget.pollEvery, () => _load());
      }
      return;
    }
    _pollUntil = null;
    final unread =
        r.status == 'NEEDS_REVIEW' &&
        r.extractionSource == null &&
        r.totalMinor == null &&
        (r.supplierName ?? '').isEmpty;
    if (unread && !_extracted.contains(r.id)) {
      _extracted.add(r.id);
      unawaited(_extract(r.id));
    }
  }

  /// Asks once before the first receipt image goes to the OCR provider.
  Future<bool> _ocrConsent() async {
    try {
      if (await AppCache.readUserData(_ocrConsentKey) == true) return true;
    } on Object {
      // ask
    }
    if (_ocrDeclined || !mounted) return false;
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text(ExpenseOcrHe.consentTitle),
        content: const Text(ExpenseOcrHe.consentBody),
        actions: [
          TextButton(
            key: const Key('expense-ocr-manual'),
            onPressed: () => Navigator.pop(context, false),
            child: const Text(ExpenseOcrHe.consentManual),
          ),
          TextButton(
            key: const Key('expense-ocr-allow'),
            onPressed: () => Navigator.pop(context, true),
            child: const Text(ExpenseOcrHe.consentAllow),
          ),
        ],
      ),
    );
    if (ok != true) {
      _ocrDeclined = true;
      return false;
    }
    try {
      await AppCache.writeUserData(_ocrConsentKey, true);
    } on Object {
      // asked again next time
    }
    return true;
  }

  Future<void> _extract(String id) async {
    if ((await _ocrTried()).contains(id) || !await _ocrConsent()) return;
    if (!mounted) return;
    unawaited(_rememberOcrTried(id));
    setState(() => _reading = id);
    try {
      final ran = await runExpenseExtraction(
        id,
      ).timeout(ExpensesScreen.readTimeout);
      // What OCR read must reach the card: a failed re-read is retried
      // (AT-19: the card stayed empty after a successful read).
      for (var i = 0; ran && mounted && i < 3; i++) {
        if (await _load()) break;
        await Future<void>.delayed(widget.pollEvery);
      }
    } on Object {
      // Manual entry.
    }
    if (mounted && _reading == id) setState(() => _reading = null);
  }

  void _next({String? message, bool skipped = false}) {
    if (_queue.isEmpty) return;
    setState(() {
      final id = _queue.removeAt(0);
      if (skipped) {
        _queue.add(id);
      } else {
        _done++;
      }
      _pollUntil = null;
    });
    if (message != null) {
      ScaffoldMessenger.of(context)
        ..hideCurrentNotchNotice()
        ..showNotchNotice(SnackBar(content: Text(message)));
    }
    _afterChange();
  }

  Future<void> _undoDuplicate(String id) async {
    try {
      await undoExpenseDuplicate(id);
      await _load();
    } on Object catch (e) {
      if (mounted) showErrorSnack(context, e);
    }
  }

  Future<void> _reject() async {
    final r = _current;
    if (r == null) return;
    final reason = await showDialog<String>(
      context: context,
      builder: (_) => const _RejectDialog(),
    );
    if (reason == null || !mounted) return;
    try {
      await rejectExpense(r.id, reason);
      HapticFeedback.mediumImpact();
      _next(message: ExpenseHe.rejected);
      unawaited(_load());
    } on Object catch (e) {
      if (mounted) showErrorSnack(context, e);
    }
  }

  void _openFromList(ExpenseRow r) {
    if (r.status == 'APPROVED' && _be44 == true && _approver) {
      setState(() => _editing = r);
      return;
    }
    if (!r.isReviewable && !r.isProcessing) return;
    setState(() {
      _queue = [r.id, ..._queue.where((id) => id != r.id)];
      _list = false;
    });
    _afterChange();
  }

  @override
  Widget build(BuildContext context) {
    final current = _current;
    final editing = _editing;
    final canReject =
        editing == null &&
        !_list &&
        current != null &&
        _approver &&
        current.isReviewable &&
        !current.isDuplicate;
    return Scaffold(
      appBar: context.isDark
          ? null
          : AppBar(
              title: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(editing != null ? ExpenseHe.editTitle : ExpenseHe.title),
                  if (editing == null && !_list && current != null)
                    Text(
                      ExpenseHe.progress(_done + 1, _done + _queue.length),
                      key: const Key('expense-progress'),
                      style: AppText.secondary.copyWith(
                        color: context.palette.muted,
                      ),
                    ),
                ],
              ),
              actions: [
                if (_rows != null && _rows!.isNotEmpty)
                  TextButton(
                    key: const Key('expense-mode'),
                    onPressed: _toggleList,
                    child: Text(
                      _list && editing == null
                          ? ExpenseHe.review
                          : ExpenseHe.allExpenses,
                    ),
                  ),
                if (editing != null)
                  MoreMenu(
                    items: [
                      MoreMenuItem(
                        label: ExpenseHe.delete,
                        destructive: true,
                        onSelected: _delete,
                      ),
                    ],
                  ),
                if (canReject)
                  MoreMenu(
                    items: [
                      MoreMenuItem(
                        label: ExpenseHe.reject,
                        destructive: true,
                        onSelected: _reject,
                      ),
                    ],
                  ),
              ],
            ),
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (context.isDark)
              Padding(
                padding: const EdgeInsets.fromLTRB(
                  Space.page,
                  Space.m,
                  Space.page,
                  Space.s,
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        editing != null ? ExpenseHe.editTitle : ExpenseHe.title,
                        style: AppText.displayTitle,
                      ),
                    ),
                    if (_rows != null && _rows!.isNotEmpty) ...[
                      TextButton(
                        key: const Key('expense-mode-dark'),
                        onPressed: _toggleList,
                        child: Text(
                          _list && editing == null
                              ? ExpenseHe.review
                              : ExpenseHe.allExpenses,
                          style: AppText.body.copyWith(
                            color: DesignTokens.lavender,
                          ),
                        ),
                      ),
                      const SizedBox(width: Space.s),
                    ],
                    const DesignBackButton(),
                  ],
                ),
              ),
            OfflineBanner(
              visible: _offline || businessContext.offline,
              onRetry: _load,
            ),
            Expanded(
              child: ContentReveal(
                key: ValueKey((
                  _rows != null,
                  _list,
                  _editing?.id,
                  _current?.id,
                )),
                child: _body(context),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _body(BuildContext context) {
    final rows = _rows;
    if (rows == null) {
      return _error != null
          ? ErrorView(
              error: _error!,
              onRetry: () {
                setState(() => _error = null);
                _load(initial: true);
              },
            )
          : const SingleChildScrollView(child: SkeletonList());
    }
    final editing = _editing;
    if (editing != null) {
      return ExpenseReviewCard(
        key: ValueKey('edit-${editing.id}'),
        row: editing,
        categories: _categories,
        approver: _approver,
        editApproved: true,
        onDone: _closeEdit,
        onSkip: () => _closeEdit(null),
        onUndoDuplicate: () async {},
      );
    }
    if (_list) return _listBody(context, rows);
    final current = _current;
    if (current == null) {
      final capture = _caps.can(Cap.expenseCapture);
      return EmptyState(
        icon: Iconsax.tick_circle,
        title: ExpenseHe.allDone,
        actionLabel: capture ? ExpenseHe.capture : null,
        onAction: capture
            ? () {
                Navigator.of(context).pop();
                openExpenseCapture(navigatorKey.currentContext ?? context);
              }
            : null,
      );
    }
    return ExpenseReviewCard(
      key: ValueKey('card-${current.id}-${current.status}'),
      row: current,
      categories: _categories,
      approver: _approver,
      reading: _reading == current.id,
      duplicateOf: current.duplicateOfExpenseId == null
          ? null
          : _row(current.duplicateOfExpenseId!),
      onDone: (message) {
        _next(message: message);
        unawaited(_load());
      },
      onSkip: () => _next(skipped: true),
      onUndoDuplicate: () => _undoDuplicate(current.id),
    );
  }

  Widget _listBody(BuildContext context, List<ExpenseRow> rows) {
    final p = context.palette;
    final server = _be44 == true ? _serverRows : null;
    final showMineChip =
        _approver &&
        _caps.can(Cap.expenseCapture) &&
        (server != null || _mine.isNotEmpty);
    final shown =
        server ??
        [
          for (final r in expenseListRows(
            rows,
            approver: _approver,
            mineOnly: _mineOnly,
            mine: _mine,
            userId: businessContext.me?.userId,
          ))
            if (expenseMatches(r, _query.text)) r,
        ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(
            Space.page,
            Space.s,
            Space.page,
            0,
          ),
          child: TextField(
            key: const Key('expense-search'),
            controller: _query,
            onChanged: _onQuery,
            textInputAction: TextInputAction.search,
            decoration: const InputDecoration(
              hintText: ExpenseHe.searchHint,
              prefixIcon: Icon(Iconsax.search_normal_1),
            ),
          ),
        ),
        if (showMineChip) ...[
          const SizedBox(height: Space.s),
          ChipRow<bool>(
            options: const [
              ChipOption(false, ExpenseHe.chipAll),
              ChipOption(true, ExpenseHe.chipMine),
            ],
            selected: _mineOnly,
            onSelected: (v) {
              setState(() => _mineOnly = v);
              _loadList();
            },
          ),
        ],
        Expanded(
          child: shown.isEmpty
              ? const EmptyState(
                  icon: Iconsax.receipt_item,
                  title: ExpenseHe.emptyList,
                )
              : ListView.builder(
                  itemCount: shown.length,
                  itemBuilder: (context, i) {
                    final r = shown[i];
                    final status = ExpenseHe.statusLabels[r.status] ?? r.status;
                    final title =
                        r.supplierName ?? r.originalFilename ?? ExpenseHe.title;
                    final editable =
                        r.status == 'APPROVED' && server != null && _approver;
                    return Semantics(
                      button: r.isReviewable || r.isProcessing || editable,
                      label: [
                        title,
                        formatDateHe(r.expenseDate),
                        status,
                      ].join(', '),
                      excludeSemantics: true,
                      child: InkWell(
                        key: Key('expense-row-${r.id}'),
                        onTap: () => _openFromList(r),
                        child: ConstrainedBox(
                          constraints: const BoxConstraints(minHeight: Hit.row),
                          child: Padding(
                            padding: const EdgeInsets.symmetric(
                              horizontal: Space.page,
                              vertical: Space.s,
                            ),
                            child: Row(
                              children: [
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        title,
                                        style: AppText.headline,
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                      Text(
                                        '${formatDateHe(r.expenseDate)} · $status',
                                        style: AppText.secondary.copyWith(
                                          color: p.muted,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                if (r.totalMinor != null)
                                  AmountText(r.totalMinor!),
                              ],
                            ),
                          ),
                        ),
                      ),
                    );
                  },
                ),
        ),
      ],
    );
  }
}

/// "למה?" — one required field (a system dialog, not a sheet, §5).
class _RejectDialog extends StatefulWidget {
  const _RejectDialog();

  @override
  State<_RejectDialog> createState() => _RejectDialogState();
}

class _RejectDialogState extends State<_RejectDialog> {
  final _reason = TextEditingController();
  bool _tried = false;

  @override
  void dispose() {
    _reason.dispose();
    super.dispose();
  }

  void _submit() {
    final t = _reason.text.trim();
    if (t.isEmpty) {
      setState(() => _tried = true);
      return;
    }
    Navigator.of(context).pop(t);
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text(ExpenseHe.rejectTitle),
    content: TextField(
      key: const Key('expense-reject-reason'),
      controller: _reason,
      autofocus: true,
      onSubmitted: (_) => _submit(),
      decoration: InputDecoration(
        hintText: ExpenseHe.rejectHint,
        errorText: _tried && _reason.text.trim().isEmpty
            ? ExpenseHe.rejectRequired
            : null,
      ),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text(CommonHe.cancel),
      ),
      TextButton(
        key: const Key('expense-reject-confirm'),
        onPressed: _submit,
        style: TextButton.styleFrom(foregroundColor: context.palette.danger),
        child: const Text(ExpenseHe.reject),
      ),
    ],
  );
}

import '../../util/labels/customer_crm_he.dart';
import '../../util/labels/people_he.dart';
import 'dart:async';
import 'dart:math' as math;
import 'package:flutter/foundation.dart' show kDebugMode;
import 'package:flutter/material.dart';
import 'package:iconsax_flutter/iconsax_flutter.dart';
import '../../api/client.dart';
import '../../api/commerce_api.dart';
import '../../api/expenses_api.dart';
import '../../api/models/models.dart';
import '../../router.dart';
import '../../state/business_context.dart';
import '../../ui/ds.dart';

const _chartColors = [
  DesignTokens.lavender,
  DesignTokens.green,
  DesignTokens.yellow,
  DesignTokens.coral,
  Color(0xFF83B9FF),
  Color(0xFFF4A5DC),
];
String _monthKey(DateTime d) =>
    '${d.year}-${d.month.toString().padLeft(2, '0')}';
const _months = [
  'ינואר',
  'פברואר',
  'מרץ',
  'אפריל',
  'מאי',
  'יוני',
  'יולי',
  'אוגוסט',
  'ספטמבר',
  'אוקטובר',
  'נובמבר',
  'דצמבר',
];
const _commonExpenseTypes = [
  'עלות מכירות: מלאי וקניות',
  'משכורות ושכר עבודה והוצאות נלוות',
  'עבודות חוץ וקבלנות משנה',
  'שירותים אחרים: ייעוץ, תוכנה, פרסום וסליקה',
  'הוצאות מימון: ריבית והפרשי הצמדה',
  'הוצאות רכב: דלק, ביטוח ואחזקה',
  'אחזקה ותיקונים שוטפים',
  'הוצאות משרדיות: ציוד, תקשורת ואינטרנט',
  'הנהלת חשבונות והגשת דוח שנתי',
  'דמי שכירות ותמלוגים',
  'הוצאות לפי תקנות: נסיעות, לינה והוצאות נוספות',
  'מיסים עירוניים, אגרות והיטלים',
  'ביטוח עסקי',
  'חובות רעים',
  'הוצאות אחרות',
  'פחת על ציוד ורכוש',
];

class ExpenseOverviewScreen extends StatefulWidget {
  const ExpenseOverviewScreen({super.key});
  @override
  State<ExpenseOverviewScreen> createState() => _ExpenseOverviewScreenState();
}

class _ExpenseOverviewScreenState extends State<ExpenseOverviewScreen> {
  DateTime _month = DateTime(DateTime.now().year, DateTime.now().month);
  ExpenseOverview? _data;
  Object? _error;
  bool _loading = true;
  bool _showingDemoData = false;
  int _generation = 0;
  String? _category, _business;
  bool _showAllExpenseTypes = false;
  List<ExpenseCategory> _categories = [];
  final GlobalKey _expenseListKey = GlobalKey();
  bool get _canShowDemoData =>
      kDebugMode && ApiClient.baseUrl == 'http://127.0.0.1:3031';
  @override
  void initState() {
    super.initState();
    _business = businessContext.business?.businessId;
    businessContext.addListener(_businessChanged);
    unawaited(_load());
  }

  @override
  void dispose() {
    businessContext.removeListener(_businessChanged);
    _generation++;
    super.dispose();
  }

  void _businessChanged() {
    if (_business != businessContext.business?.businessId) {
      _business = businessContext.business?.businessId;
      unawaited(_load());
    }
  }

  Future<void> _load() async {
    final generation = ++_generation;
    setState(() {
      _loading = true;
      _error = null;
      _showingDemoData = false;
    });
    try {
      var data = await fetchExpenseOverview(_monthKey(_month));
      final cats = await fetchExpenseCategories();
      final showDemo = _canShowDemoData && data.expenses.isEmpty;
      if (showDemo) data = _demoExpenseOverview(_monthKey(_month));
      if (mounted && generation == _generation) {
        setState(() {
          _data = data;
          _categories = cats;
          _showingDemoData = showDemo;
          _loading = false;
        });
      }
    } on Object catch (e) {
      if (mounted && generation == _generation) {
        setState(() {
          _error = e;
          _loading = false;
        });
      }
    }
  }

  void _move(int delta) {
    setState(() {
      _month = DateTime(_month.year, _month.month + delta);
      _category = null;
    });
    unawaited(_load());
  }

  Widget _demoNotice(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
    decoration: BoxDecoration(
      color: DesignTokens.lavender.withValues(alpha: .12),
      borderRadius: BorderRadius.circular(18),
      border: Border.all(color: DesignTokens.lavender.withValues(alpha: .25)),
    ),
    child: Row(
      children: [
        const Icon(Icons.visibility_outlined, color: DesignTokens.lavender),
        const SizedBox(width: 10),
        Expanded(
          child: Text(
            'נתוני תצוגה מקומיים · הנתונים אינם נשמרים ואינם משנים את החשבון',
            style: AppText.secondary.copyWith(color: context.palette.ink),
          ),
        ),
      ],
    ),
  );

  Future<void> _classify(Map<String, dynamic> row) async {
    final changed = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (_) => _RecognitionSheet(row: row, categories: _categories),
    );
    if (changed == true && mounted) await _load();
  }

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final data = _data;
    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 8, 16, 8),
              child: Row(
                children: [
                  const Expanded(
                    child: Text(
                      'הכסף יוצא.\nהתמונה ברורה.',
                      style: AppText.title,
                    ),
                  ),
                  const DesignBackButton(),
                ],
              ),
            ),
            Expanded(
              child: RefreshIndicator(
                onRefresh: _load,
                child: ListView(
                  padding: const EdgeInsets.fromLTRB(20, 8, 20, 28),
                  children: [
                    Row(
                      children: [
                        IconButton(
                          tooltip: CustomerCrmHe.previousMonth,
                          onPressed: () => _move(-1),
                          icon: const Icon(Icons.chevron_right_rounded),
                        ),
                        Expanded(
                          child: Text(
                            '${_months[_month.month - 1]} ${_month.year}',
                            textAlign: TextAlign.center,
                            style: AppText.headline,
                          ),
                        ),
                        IconButton(
                          tooltip: CustomerCrmHe.nextMonth,
                          onPressed:
                              _month.isBefore(
                                DateTime(
                                  DateTime.now().year,
                                  DateTime.now().month,
                                ),
                              )
                              ? () => _move(1)
                              : null,
                          icon: const Icon(Icons.chevron_left_rounded),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    if (_loading)
                      const SkeletonList(rows: 5)
                    else if (_error != null)
                      ErrorView(error: _error!, onRetry: _load)
                    else if (data != null)
                      ContentReveal(
                        key: ValueKey(data.month),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            if (_showingDemoData) ...[
                              _demoNotice(context),
                              const SizedBox(height: 12),
                            ],
                            AppCard(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    'סך ההוצאות החודש',
                                    style: AppText.body.copyWith(
                                      color: p.muted,
                                    ),
                                  ),
                                  const SizedBox(height: 10),
                                  AmountText(
                                    data.total,
                                    style: AppText.title.copyWith(fontSize: 42),
                                  ),
                                  const SizedBox(height: 8),
                                  Text(
                                    '${data.count} הוצאות • הסכומים כוללים מע״מ',
                                    style: AppText.secondary.copyWith(
                                      color: p.muted,
                                      fontSize: 13,
                                    ),
                                  ),
                                  const SizedBox(height: 20),
                                  Row(
                                    children: [
                                      Expanded(
                                        child: FilledButton.icon(
                                          key: const Key('expense-upload-new'),
                                          onPressed: () =>
                                              openExpenseCapture(context),
                                          icon: const Icon(
                                            Icons.add_a_photo_outlined,
                                          ),
                                          label: const Text(
                                            ExpenseHe.newExpense,
                                          ),
                                        ),
                                      ),
                                      Expanded(
                                        child: TextButton.icon(
                                          onPressed: () =>
                                              openExpenses(context),
                                          icon: const Icon(
                                            Icons.fact_check_outlined,
                                          ),
                                          label: const Text(
                                            ExpenseHe.reviewAndApprove,
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(height: 16),
                            LayoutBuilder(
                              builder: (context, c) => Wrap(
                                spacing: 12,
                                runSpacing: 12,
                                children: [
                                  _stat(
                                    context,
                                    'לפי סיווג ההוצאות',
                                    data.recognized,
                                    DesignTokens.green,
                                    Icons.check_circle_outline_rounded,
                                    c.maxWidth,
                                  ),
                                  _stat(
                                    context,
                                    'מע״מ לפי הסיווג',
                                    data.vat,
                                    DesignTokens.yellow,
                                    Icons.percent_rounded,
                                    c.maxWidth,
                                  ),
                                ],
                              ),
                            ),
                            if (data.unclassified > BigInt.zero) ...[
                              const SizedBox(height: 16),
                              Container(
                                padding: const EdgeInsets.all(16),
                                decoration: BoxDecoration(
                                  color: DesignTokens.yellow.withValues(
                                    alpha: 0.08,
                                  ),
                                  borderRadius: BorderRadius.circular(24),
                                ),
                                child: Row(
                                  children: [
                                    Icon(
                                      Icons.auto_awesome_outlined,
                                      color: p.warn,
                                    ),
                                    const SizedBox(width: 12),
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          const Text(
                                            'יש הוצאות שממתינות לסיווג',
                                            style: AppText.headline,
                                          ),
                                          const SizedBox(height: 4),
                                          AmountText(
                                            data.unclassified,
                                            style: AppText.body,
                                            color: p.muted,
                                          ),
                                          const SizedBox(height: 8),
                                          TextButton.icon(
                                            onPressed: () {
                                              final target = _expenseListKey
                                                  .currentContext;
                                              if (target != null) {
                                                unawaited(
                                                  Scrollable.ensureVisible(
                                                    target,
                                                    duration: context.motion(
                                                      350,
                                                    ),
                                                    curve: Curves.easeOutCubic,
                                                  ),
                                                );
                                              }
                                            },
                                            icon: const Icon(
                                              Icons.tune_rounded,
                                              size: 17,
                                            ),
                                            label: const Text(
                                              ExpenseHe.classifyExpenses,
                                            ),
                                            style: TextButton.styleFrom(
                                              padding: EdgeInsets.zero,
                                              minimumSize: const Size(0, 36),
                                              alignment: Alignment.centerRight,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                            const SizedBox(height: 24),
                            if (data.categories.isNotEmpty)
                              AppCard(
                                child: Column(
                                  crossAxisAlignment:
                                      CrossAxisAlignment.stretch,
                                  children: [
                                    const Text(
                                      'לאן הכסף הולך?',
                                      style: AppText.title,
                                    ),
                                    const SizedBox(height: 20),
                                    TweenAnimationBuilder<double>(
                                      tween: Tween(begin: 0, end: 1),
                                      duration: context.motion(650),
                                      curve: Curves.easeOutCubic,
                                      builder: (context, value, _) => SizedBox(
                                        height: 184,
                                        child: Stack(
                                          alignment: Alignment.center,
                                          children: [
                                            Semantics(
                                              label:
                                                  'התפלגות הוצאות לפי קטגוריה',
                                              child: CustomPaint(
                                                size: const Size(184, 184),
                                                painter: _DonutPainter([
                                                  for (final c
                                                      in data.categories)
                                                    BigInt.parse(
                                                      c['totalMinor'] as String,
                                                    ).toDouble(),
                                                ], value),
                                              ),
                                            ),
                                            Column(
                                              mainAxisSize: MainAxisSize.min,
                                              children: [
                                                Text(
                                                  '${data.categories.length}',
                                                  style: AppText.title.copyWith(
                                                    fontSize: 34,
                                                  ),
                                                ),
                                                Text(
                                                  'קטגוריות',
                                                  style: AppText.secondary
                                                      .copyWith(color: p.muted),
                                                ),
                                              ],
                                            ),
                                          ],
                                        ),
                                      ),
                                    ),
                                    const SizedBox(height: 18),
                                    for (
                                      var i = 0;
                                      i < data.categories.length;
                                      i++
                                    )
                                      _categoryRow(
                                        data.categories[i],
                                        i,
                                        data.total,
                                        data.expenses,
                                      ),
                                    if (_category != null)
                                      TextButton(
                                        onPressed: () =>
                                            setState(() => _category = null),
                                        child: const Text(
                                          ExpenseHe.showAllCategories,
                                        ),
                                      ),
                                  ],
                                ),
                              ),
                            const SizedBox(height: 12),
                            _expenseTypeCatalog(context),
                            const SizedBox(height: 16),
                            if (data.trend.isNotEmpty)
                              _trendChart(context, data.trend),
                            const SizedBox(height: 24),
                            KeyedSubtree(
                              key: _expenseListKey,
                              child: Wrap(
                                alignment: WrapAlignment.spaceBetween,
                                crossAxisAlignment: WrapCrossAlignment.center,
                                spacing: 12,
                                children: [
                                  Text(
                                    _category ?? 'ההוצאות שלך',
                                    style: AppText.title,
                                  ),
                                  TextButton(
                                    onPressed: () => openExpenses(context),
                                    child: const Text(
                                      ExpenseHe.allExpensesAction,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            if (data.expenses.isEmpty)
                              EmptyState(
                                icon: Icons.receipt_long_outlined,
                                title: 'החודש מתחיל נקי',
                                actionLabel: 'מוסיפים הוצאה',
                                onAction: () => openExpenseCapture(context),
                              ),
                            for (final row
                                in data.expenses
                                    .where(
                                      (r) =>
                                          _category == null ||
                                          r['categoryName'] == _category,
                                    )
                                    .take(30))
                              Padding(
                                padding: const EdgeInsets.only(bottom: 10),
                                child: AppCard(
                                  onTap: _showingDemoData
                                      ? null
                                      : () => _classify(row),
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.stretch,
                                    children: [
                                      Row(
                                        children: [
                                          Expanded(
                                            child: Text(
                                              row['supplierName'] as String? ??
                                                  'ללא ספק',
                                              style: AppText.headline,
                                            ),
                                          ),
                                          const SizedBox(width: 8),
                                          Flexible(
                                            child: AmountText(
                                              BigInt.parse(
                                                row['totalMinor'] as String? ??
                                                    '0',
                                              ),
                                              style: AppText.amountRow,
                                            ),
                                          ),
                                        ],
                                      ),
                                      const SizedBox(height: 8),
                                      Wrap(
                                        spacing: 8,
                                        runSpacing: 6,
                                        children: [
                                          Text(
                                            row['categoryName'] as String? ??
                                                'ללא סיווג',
                                            style: AppText.secondary.copyWith(
                                              color: p.muted,
                                            ),
                                          ),
                                          Text(
                                            row['expenseDate'] as String? ?? '',
                                            style: AppText.secondary.copyWith(
                                              color: p.muted,
                                            ),
                                          ),
                                          Text(
                                            _classificationLabel(
                                              row['classification'] as String?,
                                            ),
                                            style: AppText.secondary.copyWith(
                                              color:
                                                  row['classification'] ==
                                                      'REVIEW'
                                                  ? p.warn
                                                  : p.accent,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            const SizedBox(height: 12),
                            Text(
                              data.note,
                              style: AppText.secondary.copyWith(
                                fontSize: 12,
                                color: p.muted,
                                height: 1.6,
                              ),
                            ),
                          ],
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _stat(
    BuildContext context,
    String label,
    BigInt amount,
    Color color,
    IconData icon,
    double width,
  ) => SizedBox(
    width: MediaQuery.textScalerOf(context).scale(15) > 21
        ? width
        : (width - 12) / 2,
    child: AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: color),
          const SizedBox(height: 10),
          Text(
            label,
            style: AppText.secondary.copyWith(
              fontSize: 13,
              color: context.palette.muted,
            ),
          ),
          const SizedBox(height: 6),
          AmountText(amount, style: AppText.title.copyWith(fontSize: 24)),
        ],
      ),
    ),
  );

  Widget _expenseTypeCatalog(BuildContext context) {
    final p = context.palette;
    final names = <String>{
      ..._commonExpenseTypes,
      ..._categories.map((category) => category.name),
    }.toList();
    final visible = _showAllExpenseTypes ? names : names.take(5).toList();
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: DesignTokens.lavender.withValues(alpha: .16),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: const Icon(
                  Iconsax.category,
                  color: DesignTokens.lavender,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'קטגוריות הוצאה לפי טופס 1320',
                      style: AppText.headline,
                    ),
                    Text(
                      '${names.length} סעיפי הוצאה',
                      style: AppText.secondary.copyWith(color: p.muted),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            'סעיפי טופס 1320. שיעור ההכרה נקבע לכל הוצאה לפי סוגה, השימוש בפועל והכללים החלים.',
            style: AppText.secondary.copyWith(color: p.muted, height: 1.45),
          ),
          const SizedBox(height: 12),
          AnimatedSize(
            duration: context.motion(260),
            curve: Curves.easeOutCubic,
            child: Column(
              children: [
                for (final name in visible)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 5),
                    child: Row(
                      children: [
                        Icon(
                          _categoryIcon(name),
                          size: 19,
                          color: DesignTokens.lavender,
                        ),
                        const SizedBox(width: 10),
                        Expanded(child: Text(name, style: AppText.body)),
                      ],
                    ),
                  ),
              ],
            ),
          ),
          TextButton.icon(
            key: const Key('expense-show-all-types'),
            onPressed: () =>
                setState(() => _showAllExpenseTypes = !_showAllExpenseTypes),
            icon: Icon(
              _showAllExpenseTypes ? Iconsax.arrow_up_2 : Iconsax.arrow_down_1,
            ),
            label: Text(
              _showAllExpenseTypes
                  ? ExpenseHe.showLess
                  : ExpenseHe.showAllExpenseTypes,
            ),
          ),
          const SizedBox(height: Space.s),
          SizedBox(
            height: Hit.primary,
            child: FilledButton.icon(
              key: const Key('expense-upload-new-catalog'),
              onPressed: () => openExpenseCapture(context),
              icon: const Icon(Iconsax.document_upload),
              label: const Text(ExpenseHe.uploadExpenseAction),
            ),
          ),
          const SizedBox(height: Space.m),
          Text(
            'הרשימה מבוססת על סעיפי ההוצאות בטופס 1320. ההכרה בפועל תלויה בשימוש העסקי, באסמכתאות ובתקנות; מומלץ לאשר את הסיווג עם רואה החשבון.',
            style: AppText.secondary.copyWith(
              color: p.muted,
              fontSize: 13,
              height: 1.45,
            ),
          ),
        ],
      ),
    );
  }

  Widget _trendChart(BuildContext context, List<Map<String, dynamic>> rows) {
    final p = context.palette;
    final visibleRows = rows.length > 8 ? rows.sublist(rows.length - 8) : rows;
    final maxAmount = visibleRows
        .map((row) => BigInt.parse(row['totalMinor'] as String))
        .fold<BigInt>(BigInt.zero, (a, b) => a > b ? a : b);
    final selected = visibleRows.where(
      (row) => row['month'] == _monthKey(_month),
    );
    final selectedAmount = selected.isEmpty
        ? BigInt.zero
        : BigInt.parse(selected.first['totalMinor'] as String);

    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          LayoutBuilder(
            builder: (context, constraints) {
              final largeText = MediaQuery.textScalerOf(context).scale(14) > 19;
              final header = Row(
                children: [
                  Container(
                    width: 38,
                    height: 38,
                    decoration: BoxDecoration(
                      color: DesignTokens.lavender.withValues(alpha: .14),
                      borderRadius: BorderRadius.circular(13),
                    ),
                    child: const Icon(
                      Icons.bar_chart_rounded,
                      color: DesignTokens.lavender,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text('הוצאות לאורך זמן', style: AppText.headline),
                        Text(
                          '${_months[_month.month - 1]} ${_month.year}',
                          style: AppText.secondary.copyWith(color: p.muted),
                        ),
                      ],
                    ),
                  ),
                  if (!largeText)
                    AmountText(selectedAmount, style: AppText.amountRow),
                ],
              );
              if (!largeText) return header;
              return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  header,
                  const SizedBox(height: 8),
                  Align(
                    alignment: AlignmentDirectional.centerStart,
                    child: AmountText(selectedAmount, style: AppText.amountRow),
                  ),
                ],
              );
            },
          ),
          const SizedBox(height: 20),
          SizedBox(
            key: const Key('expense-trend-chart'),
            height: 160,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                for (final row in visibleRows)
                  Expanded(
                    child: Center(
                      child: ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 46),
                        child: _trendBar(
                          context,
                          row,
                          maxAmount,
                          selected: row['month'] == _monthKey(_month),
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'לחצו על חודש כדי לראות את ההוצאות שלו',
            textAlign: TextAlign.center,
            style: AppText.secondary.copyWith(color: p.muted, fontSize: 12),
          ),
        ],
      ),
    );
  }

  Widget _trendBar(
    BuildContext context,
    Map<String, dynamic> row,
    BigInt maxAmount, {
    required bool selected,
  }) {
    final p = context.palette;
    final monthKey = row['month'] as String;
    final value = BigInt.parse(row['totalMinor'] as String);
    final fraction = maxAmount == BigInt.zero
        ? 0.0
        : value.toDouble() / maxAmount.toDouble();
    final parts = monthKey.split('-');
    final monthNumber = int.tryParse(parts.last) ?? 1;
    final shortMonth = _months[monthNumber - 1].substring(0, 3);
    return Semantics(
      button: true,
      label: '$shortMonth, ${_formatMinorForA11y(value)} שקלים הוצאות',
      selected: selected,
      child: Tooltip(
        message: '$shortMonth · ${_formatMinorForA11y(value)} ₪',
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: () {
            if (monthKey == _monthKey(_month)) return;
            final date = DateTime.tryParse('$monthKey-01');
            if (date == null || date.isAfter(DateTime.now())) return;
            setState(() {
              _month = DateTime(date.year, date.month);
              _category = null;
            });
            unawaited(_load());
          },
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 3),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                Expanded(
                  child: Align(
                    alignment: Alignment.bottomCenter,
                    child: TweenAnimationBuilder<double>(
                      tween: Tween(begin: 0, end: fraction),
                      duration: context.motion(650),
                      curve: Curves.easeOutCubic,
                      builder: (context, progress, _) => FractionallySizedBox(
                        heightFactor: progress.clamp(.035, 1),
                        widthFactor: selected ? .74 : .58,
                        alignment: Alignment.bottomCenter,
                        child: DecoratedBox(
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(10),
                            gradient: LinearGradient(
                              begin: Alignment.topCenter,
                              end: Alignment.bottomCenter,
                              colors: selected
                                  ? [
                                      DesignTokens.lavender,
                                      DesignTokens.lavender.withValues(
                                        alpha: .42,
                                      ),
                                    ]
                                  : [
                                      DesignTokens.lavender.withValues(
                                        alpha: .68,
                                      ),
                                      DesignTokens.lavender.withValues(
                                        alpha: .18,
                                      ),
                                    ],
                            ),
                            boxShadow: selected
                                ? [
                                    BoxShadow(
                                      color: DesignTokens.lavender.withValues(
                                        alpha: .2,
                                      ),
                                      blurRadius: 12,
                                      offset: const Offset(0, 3),
                                    ),
                                  ]
                                : null,
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  shortMonth,
                  maxLines: 1,
                  style: AppText.secondary.copyWith(
                    color: selected ? p.ink : p.muted,
                    fontSize: 11,
                    fontWeight: selected ? FontWeight.w700 : FontWeight.w400,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _categoryRow(
    Map<String, dynamic> category,
    int index,
    BigInt total,
    List<Map<String, dynamic>> expenses,
  ) {
    final amount = BigInt.parse(category['totalMinor'] as String);
    final name = category['name'] as String;
    final categoryExpenses = expenses.where(
      (expense) => expense['categoryName'] == name,
    );
    var classifiedMinor = BigInt.zero;
    var recognizedMinor = BigInt.zero;
    for (final expense in categoryExpenses) {
      final recognized = expense['recognizedMinor'];
      final expenseTotal = expense['totalMinor'];
      if (recognized is String && expenseTotal is String) {
        classifiedMinor += BigInt.tryParse(expenseTotal) ?? BigInt.zero;
        recognizedMinor += BigInt.tryParse(recognized) ?? BigInt.zero;
      }
    }
    final recognizedPercent = classifiedMinor > BigInt.zero
        ? recognizedMinor * BigInt.from(100) ~/ classifiedMinor
        : null;
    return InkWell(
      onTap: () => setState(() => _category = _category == name ? null : name),
      borderRadius: BorderRadius.circular(14),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Container(
                  width: 38,
                  height: 38,
                  decoration: BoxDecoration(
                    color: _chartColors[index % _chartColors.length].withValues(
                      alpha: .16,
                    ),
                    shape: BoxShape.circle,
                  ),
                  child: Icon(
                    _categoryIcon(name),
                    color: _chartColors[index % _chartColors.length],
                    size: 19,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: AppText.body,
                  ),
                ),
                const SizedBox(width: 8),
                Flexible(child: AmountText(amount, style: AppText.secondary)),
                const SizedBox(width: 10),
                Text(
                  '${total > BigInt.zero ? (amount * BigInt.from(100) ~/ total) : 0}%',
                  textDirection: TextDirection.ltr,
                  style: AppText.secondary.copyWith(
                    color: _category == name
                        ? context.palette.ink
                        : context.palette.muted,
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 3),
            Padding(
              padding: const EdgeInsetsDirectional.only(start: 50),
              child: Row(
                children: [
                  Icon(
                    recognizedPercent == null
                        ? Iconsax.info_circle
                        : Iconsax.tick_circle,
                    size: 14,
                    color: recognizedPercent == null
                        ? context.palette.muted
                        : DesignTokens.green,
                  ),
                  const SizedBox(width: 5),
                  Expanded(
                    child: Text(
                      recognizedPercent == null
                          ? 'טרם סווגו הוצאות בתחום'
                          : 'מוכר לפי הסיווג: $recognizedPercent% · ${moneyInline(recognizedMinor)}',
                      style: AppText.secondary.copyWith(
                        color: context.palette.muted,
                        fontSize: 12,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

IconData _categoryIcon(String name) {
  final value = name.toLowerCase();
  if (value.contains('נסיע') ||
      value.contains('רכב') ||
      value.contains('דלק')) {
    return Icons.directions_car_filled_outlined;
  }
  if (value.contains('תוכנה') ||
      value.contains('שירות') ||
      value.contains('מנוי')) {
    return Icons.computer_rounded;
  }
  if (value.contains('משרד') || value.contains('ציוד')) {
    return Icons.work_outline_rounded;
  }
  if (value.contains('מזון') ||
      value.contains('אוכל') ||
      value.contains('אירוח')) {
    return Icons.restaurant_outlined;
  }
  if (value.contains('תקשורת') ||
      value.contains('טלפון') ||
      value.contains('אינטרנט')) {
    return Icons.wifi_rounded;
  }
  if (value.contains('פרסום') || value.contains('שיווק')) {
    return Icons.campaign_outlined;
  }
  if (value.contains('מקצוע') || value.contains('ייעוץ')) {
    return Icons.support_agent_rounded;
  }
  return Icons.receipt_long_outlined;
}

String _formatMinorForA11y(BigInt minor) =>
    (minor ~/ BigInt.from(100)).toString();

ExpenseOverview _demoExpenseOverview(String selectedMonth) {
  final selected = DateTime.tryParse('$selectedMonth-01') ?? DateTime.now();
  final months = [
    for (var offset = 5; offset >= 0; offset--)
      DateTime(selected.year, selected.month - offset),
  ];
  final monthlyRows = <String, List<Map<String, dynamic>>>{};
  for (var i = 0; i < months.length; i++) {
    final date = months[i];
    final key = _monthKey(date);
    final entries = <(int, String, String, String, int, int, String, int, int)>[
      (
        4,
        'כלים דיגיטליים לעסק',
        'תוכנה ושירותים',
        'software',
        129900 + i * 15000,
        19815 + i * 2288,
        'BUSINESS',
        100,
        100,
      ),
      (
        10,
        'נסיעה לפגישת לקוח',
        'נסיעות ורכב',
        'travel',
        236000 + i * 11000,
        36000 + i * 1650,
        'MIXED',
        50,
        50,
      ),
      (
        17,
        'ציוד וחומרים למשרד',
        'ציוד משרדי',
        'office',
        47200 + i * 5000,
        7200 + i * 760,
        'REVIEW',
        0,
        0,
      ),
      (
        23,
        'קידום העסק ברשת',
        'שיווק ופרסום',
        'marketing',
        118000 + i * 8000,
        18000 + i * 1200,
        'BUSINESS',
        100,
        100,
      ),
    ];
    monthlyRows[key] = [
      for (final row in entries)
        _demoExpenseRow(
          id: 'demo-$key-${row.$4}',
          supplier: row.$2,
          category: row.$3,
          categoryId: 'demo-${row.$4}',
          date: '$key-${row.$1.toString().padLeft(2, '0')}',
          total: row.$5,
          vat: row.$6,
          classification: row.$7,
          expensePercent: row.$8,
          vatPercent: row.$9,
        ),
    ];
  }

  final selectedRows = monthlyRows[selectedMonth] ?? const [];
  final categoryTotals = <String, ({int total, int count})>{};
  var total = 0;
  var recognized = 0;
  var vat = 0;
  var unclassified = 0;
  for (final row in selectedRows) {
    final amount = int.parse(row['totalMinor'] as String);
    total += amount;
    final rowRecognized = row['recognizedMinor'] as String?;
    if (rowRecognized == null) {
      unclassified += amount;
    } else {
      recognized += int.parse(rowRecognized);
      vat += int.parse(row['recoverableVatMinor'] as String);
    }
    final name = row['categoryName'] as String;
    final current = categoryTotals[name] ?? (total: 0, count: 0);
    categoryTotals[name] = (
      total: current.total + amount,
      count: current.count + 1,
    );
  }
  return ExpenseOverview.fromJson({
    'month': selectedMonth,
    'totalMinor': '$total',
    'recognizedMinor': '$recognized',
    'recoverableVatMinor': '$vat',
    'unclassifiedMinor': '$unclassified',
    'count': selectedRows.length,
    'categories': [
      for (final entry in categoryTotals.entries)
        {
          'name': entry.key,
          'totalMinor': '${entry.value.total}',
          'count': entry.value.count,
        },
    ],
    'trend': [
      for (final month in months)
        {
          'month': _monthKey(month),
          'totalMinor':
              '${(monthlyRows[_monthKey(month)] ?? const []).fold<int>(0, (sum, row) => sum + int.parse(row['totalMinor'] as String))}',
        },
    ],
    'expenses': selectedRows,
    'recognitionNote':
        'נתוני הדגמה חזותיים בלבד. בחשבון אמיתי החישובים והסיווגים מתקבלים מהשרת.',
  });
}

Map<String, dynamic> _demoExpenseRow({
  required String id,
  required String supplier,
  required String category,
  required String categoryId,
  required String date,
  required int total,
  required int vat,
  required String classification,
  required int expensePercent,
  required int vatPercent,
}) {
  final recoverableVat = vat * vatPercent ~/ 100;
  final recognized = classification == 'REVIEW'
      ? null
      : (total - recoverableVat) * expensePercent ~/ 100;
  return {
    'id': id,
    'supplierName': supplier,
    'totalMinor': '$total',
    'vatMinor': '$vat',
    'expenseDate': date,
    'categoryName': category,
    'categoryId': categoryId,
    'classification': classification,
    'expensePercent': classification == 'REVIEW' ? null : expensePercent,
    'vatPercent': classification == 'REVIEW' ? null : vatPercent,
    'recognizedMinor': recognized?.toString(),
    'recoverableVatMinor': '$recoverableVat',
    'status': 'APPROVED',
  };
}

String _classificationLabel(String? value) => switch (value) {
  'BUSINESS' => 'עסקית',
  'MIXED' => 'שימוש מעורב',
  'PERSONAL' => 'פרטית',
  _ => 'ממתינה לסיווג',
};

class _DonutPainter extends CustomPainter {
  const _DonutPainter(this.values, this.progress);
  final List<double> values;
  final double progress;
  @override
  void paint(Canvas canvas, Size size) {
    final rect = Rect.fromCircle(
      center: Offset(size.width / 2, size.height / 2),
      radius: math.min(size.width, size.height) / 2 - 14,
    );
    final total = values.fold<double>(0, (a, b) => a + b);
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 22
      ..strokeCap = StrokeCap.round;
    if (total <= 0) return;
    var angle = -math.pi / 2;
    for (var i = 0; i < values.length; i++) {
      final sweep = values[i] / total * math.pi * 2;
      paint.color = _chartColors[i % _chartColors.length];
      canvas.drawArc(
        rect,
        angle + 0.025,
        math.max(0, sweep - 0.05) * progress,
        false,
        paint,
      );
      angle += sweep;
    }
  }

  @override
  bool shouldRepaint(_DonutPainter old) =>
      old.progress != progress || old.values != values;
}

class _RecognitionSheet extends StatefulWidget {
  const _RecognitionSheet({required this.row, required this.categories});
  final Map<String, dynamic> row;
  final List<ExpenseCategory> categories;
  @override
  State<_RecognitionSheet> createState() => _RecognitionSheetState();
}

class _RecognitionSheetState extends State<_RecognitionSheet> {
  late String _classification =
      widget.row['classification'] as String? ?? 'REVIEW';
  late int? _expense = widget.row['expensePercent'] as int?,
      _vat = businessContext.isVatExempt ? 0 : widget.row['vatPercent'] as int?;
  late String? _category = widget.row['categoryId'] as String?;
  late final TextEditingController _note = TextEditingController(
    text: widget.row['note'] as String? ?? '',
  );
  bool _busy = false;
  String? _error;
  @override
  void dispose() {
    _note.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (_classification != 'REVIEW' &&
        widget.categories.isNotEmpty &&
        (_category == null ||
            !widget.categories.any((category) => category.id == _category))) {
      setState(() => _error = 'יש לבחור תחום כדי לעדכן את סיכום ההוצאות');
      return;
    }
    if (_classification != 'REVIEW' &&
        _classification != 'PERSONAL' &&
        (_expense == null || _vat == null)) {
      setState(() => _error = 'יש לבחור אחוז הכרה ואחוז מע״מ בנפרד');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await saveExpenseRecognition(
        widget.row['id'] as String,
        classification: _classification,
        expensePercent: _classification == 'PERSONAL' ? 0 : _expense,
        vatPercent: _classification == 'PERSONAL' || businessContext.isVatExempt
            ? 0
            : _vat,
        note: _note.text,
        categoryId: _category,
      );
      if (mounted) Navigator.pop(context, true);
    } on Object {
      if (mounted) {
        setState(
          () => _error = 'הסיווג לא נשמר. יש לבדוק את החיבור ולנסות שוב.',
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => SafeArea(
    top: false,
    child: SingleChildScrollView(
      padding: EdgeInsets.fromLTRB(
        20,
        0,
        20,
        MediaQuery.viewInsetsOf(context).bottom + 24,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SheetTitle(
            'מסדרים את ההוצאה',
            subtitle: widget.row['supplierName'] as String? ?? '',
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Icon(Icons.category_outlined, color: context.palette.accent),
              const SizedBox(width: 10),
              const Expanded(
                child: Text(
                  'לאיזה תחום שייכת ההוצאה?',
                  style: AppText.headline,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          if (widget.categories.isNotEmpty)
            DropdownButtonFormField<String>(
              key: const Key('expense-recognition-category'),
              initialValue: widget.categories.any((c) => c.id == _category)
                  ? _category
                  : null,
              isExpanded: true,
              decoration: InputDecoration(
                prefixIcon: const Icon(Icons.folder_open_rounded),
                hintText: 'בחירת תחום',
                filled: true,
                fillColor: context.palette.surface.withValues(alpha: .7),
              ),
              items: [
                for (final c in widget.categories)
                  DropdownMenuItem(
                    value: c.id,
                    child: Row(
                      children: [
                        Icon(_categoryIcon(c.name), size: 18),
                        const SizedBox(width: 10),
                        Expanded(child: Text(c.name)),
                      ],
                    ),
                  ),
              ],
              onChanged: _busy ? null : (v) => setState(() => _category = v),
            )
          else
            Container(
              padding: const EdgeInsets.all(13),
              decoration: BoxDecoration(
                color: context.palette.surface,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: context.palette.line),
              ),
              child: Row(
                children: [
                  Icon(
                    Icons.info_outline_rounded,
                    color: context.palette.muted,
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      'לא הוגדרו תחומי הוצאה לעסק. הסיכום יישאר לפי הסיווג עד שיוגדרו תחומים.',
                      style: AppText.secondary.copyWith(
                        color: context.palette.muted,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          const SizedBox(height: 20),
          const Text('איך ההוצאה משמשת את העסק?', style: AppText.headline),
          const SizedBox(height: 10),
          ChipRow<String>(
            padding: EdgeInsets.zero,
            options: const [
              ChipOption('BUSINESS', 'עסקית'),
              ChipOption('MIXED', 'מעורבת'),
              ChipOption('PERSONAL', 'פרטית'),
              ChipOption('REVIEW', 'לבדיקת רו״ח'),
            ],
            selected: _classification,
            onSelected: (v) => setState(() => _classification = v),
          ),
          if (_classification == 'BUSINESS' || _classification == 'MIXED') ...[
            const SizedBox(height: 20),
            const Text('אחוז הכרה בהוצאה', style: AppText.headline),
            const SizedBox(height: 10),
            ChipRow<int>(
              padding: EdgeInsets.zero,
              options: [
                for (final p in [0, 25, 50, 75, 100]) ChipOption(p, '$p%'),
              ],
              selected: _expense,
              onSelected: (v) => setState(() => _expense = v),
            ),
            const SizedBox(height: 20),
            if (businessContext.isVatExempt)
              const Text(
                'לעוסק פטור לא מחושב קיזוז מע״מ תשומות',
                style: AppText.secondary,
              )
            else ...[
              const Text('אחוז מע״מ לקיזוז', style: AppText.headline),
              const SizedBox(height: 10),
              ChipRow<int>(
                padding: EdgeInsets.zero,
                options: [
                  for (final p in [0, 25, 50, 75, 100]) ChipOption(p, '$p%'),
                ],
                selected: _vat,
                onSelected: (v) => setState(() => _vat = v),
              ),
            ],
          ],
          const SizedBox(height: 20),
          TextField(
            controller: _note,
            maxLength: 500,
            maxLines: 2,
            decoration: const InputDecoration(labelText: 'הערה לסיווג'),
          ),
          const SizedBox(height: 8),
          Text(
            'הסיווג אינו קביעה לצורכי מס. יש להתאים את האחוזים לאופי השימוש ולבדיקת רואה החשבון.',
            style: AppText.secondary.copyWith(
              color: context.palette.muted,
              fontSize: 12,
              height: 1.5,
            ),
          ),
          if (_error != null)
            Text(
              _error!,
              style: AppText.body.copyWith(color: context.palette.danger),
            ),
          const SizedBox(height: 20),
          PrimaryButton(
            label: ExpenseHe.savingClassification,
            loadingText: _busy ? ExpenseHe.savingInProgress : null,
            onPressed: _save,
          ),
        ],
      ),
    ),
  );
}

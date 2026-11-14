// Design-system gallery (debug only). INT may route to it behind kDebugMode;
// release builds render nothing.

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../util/money.dart';
import '../util/status_map.dart';
import 'ds.dart';
import '../util/labels/labels.dart';
import 'package:iconsax_flutter/iconsax_flutter.dart';

/// Every DS component in one scrolling page, with light/dark, 100%/200%
/// text and "הסתר סכומים" switches.
class DsGallery extends StatefulWidget {
  const DsGallery({super.key});

  @override
  State<DsGallery> createState() => _DsGalleryState();
}

class _DsGalleryState extends State<DsGallery> {
  bool _dark = false;
  bool _bigText = false;
  bool _hidden = false;
  bool _offline = false;
  String _chip = 'all';
  String _keypad = '1180';

  @override
  Widget build(BuildContext context) {
    if (!kDebugMode) return const SizedBox.shrink();
    return Theme(
      data: buildTheme(_dark ? Brightness.dark : Brightness.light),
      child: MediaQuery(
        data: MediaQuery.of(
          context,
        ).copyWith(textScaler: TextScaler.linear(_bigText ? 2 : 1)),
        child: AmountPrivacy(
          hidden: _hidden,
          child: Builder(builder: _page),
        ),
      ),
    );
  }

  Widget _page(BuildContext context) {
    final p = context.palette;
    Widget section(String title, Widget child) => Padding(
      padding: const EdgeInsets.only(top: Space.section),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: Space.page,
              vertical: Space.s,
            ),
            child: Text(
              title,
              style: AppText.secondary.copyWith(color: p.muted),
            ),
          ),
          PrimaryScope(child: child),
        ],
      ),
    );
    Widget pad(Widget w) => Padding(
      padding: const EdgeInsets.symmetric(horizontal: Space.page),
      child: w,
    );
    return Scaffold(
      appBar: AppBar(
        title: const Text('מערכת עיצוב'),
        actions: [
          MoreMenu(
            items: [
              MoreMenuItem(
                label: DocumentHe.cancelOrCredit,
                destructive: true,
                onSelected: () {},
              ),
              MoreMenuItem(
                label: CommonHe.share,
                icon: Iconsax.export_1,
                onSelected: () {},
              ),
              MoreMenuItem(
                label: DocumentHe.duplicate,
                icon: Iconsax.copy,
                onSelected: () {},
              ),
            ],
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.only(bottom: Space.xxl),
        children: [
          SwitchListTile(
            title: const Text('מצב כהה'),
            value: _dark,
            onChanged: (v) => setState(() => _dark = v),
          ),
          SwitchListTile(
            title: const Text('טקסט 200%'),
            value: _bigText,
            onChanged: (v) => setState(() => _bigText = v),
          ),
          SwitchListTile(
            title: const Text('הסתר סכומים'),
            value: _hidden,
            onChanged: (v) => setState(() => _hidden = v),
          ),
          SwitchListTile(
            title: const Text('אופליין'),
            value: _offline,
            onChanged: (v) => setState(() => _offline = v),
          ),
          OfflineBanner(visible: _offline, onRetry: () {}),
          section(
            'MoneyCard',
            pad(
              MoneyCard(
                label: 'מגיע לך',
                amountMinor: BigInt.from(1240000),
                secondaryLabel: 'מתוכם באיחור',
                secondaryMinor: BigInt.from(320000),
                onTap: () {},
              ),
            ),
          ),
          section(
            'IntentButton',
            pad(
              Row(
                children: [
                  Expanded(
                    child: IntentButton(
                      icon: Iconsax.tick_circle,
                      label: CommonHe.paid,
                      emphasized: true,
                      onPressed: () {},
                    ),
                  ),
                  const SizedBox(width: Space.m),
                  Expanded(
                    child: IntentButton(
                      icon: Iconsax.send_2,
                      label: CommonHe.requestPayment,
                      onPressed: () {},
                    ),
                  ),
                ],
              ),
            ),
          ),
          section(
            'InboxCard',
            pad(
              Column(
                children: [
                  InboxCard(
                    icon: Iconsax.verify,
                    title: '2 ממתינים לאישורך',
                    amountMinor: BigInt.from(740000),
                    actionLabel: 'פתח',
                    tone: InboxTone.attention,
                    onAction: () {},
                  ),
                  const SizedBox(height: Space.m),
                  InboxCard(
                    icon: Iconsax.gallery,
                    title: 'הוסף לוגו למסמכים',
                    actionLabel: 'הוסף',
                    onAction: () {},
                    onDismiss: () {},
                  ),
                ],
              ),
            ),
          ),
          section(
            'DocRow + StatusPill',
            Column(
              children: [
                DocRow(
                  title: 'דנה כהן',
                  subtitle: 'חשבונית מס 1042',
                  amountMinor: BigInt.from(118000),
                  status: const StatusPill.doc(DocStatus.awaitingPayment),
                  attributes: const ['נשלח'],
                  onTap: () {},
                  swipeLabel: 'קיבלתי תשלום',
                  onSwipe: () {},
                ),
                DocRow(
                  title: 'רון לוי',
                  subtitle: 'חשבון עסקה 77',
                  amountMinor: BigInt.from(820000),
                  status: const StatusPill.doc(DocStatus.overdue),
                  onTap: () {},
                ),
                DocRow(
                  title: 'נועה ברק',
                  subtitle: 'הצעת מחיר 12',
                  amountMinor: BigInt.from(60000),
                  status: const StatusPill.quote(QuoteListStatus.withCustomer),
                  onTap: () {},
                ),
              ],
            ),
          ),
          section(
            'StatusPill',
            pad(
              Wrap(
                spacing: Space.s,
                runSpacing: Space.s,
                children: [
                  for (final s in DocStatus.values) StatusPill.doc(s),
                  for (final s in QuoteListStatus.values) StatusPill.quote(s),
                ],
              ),
            ),
          ),
          section(
            'PersonRow',
            Column(
              children: [
                PersonRow(
                  name: 'דנה כהן',
                  subtitle: '050-123-4567',
                  amountLabel: 'חייב לך',
                  amountMinor: BigInt.from(599000),
                  onTap: () {},
                ),
                PersonRow(
                  name: 'אבי ספקים בע"מ',
                  subtitle: 'avi@example.com',
                  badge: 'ספק',
                  onTap: () {},
                ),
              ],
            ),
          ),
          section(
            'ChipRow',
            ChipRow<String>(
              options: const [
                ChipOption('all', 'הכל'),
                ChipOption('unpaid', 'לא שולם'),
                ChipOption('drafts', 'טיוטות'),
                ChipOption('quotes', 'הצעות'),
              ],
              selected: _chip,
              onSelected: (v) => setState(() => _chip = v),
            ),
          ),
          section(
            'SummaryCard',
            pad(
              SummaryCard(
                children: [
                  SummaryRow(
                    icon: Iconsax.note_text,
                    value: 'תיקון דוד',
                    onTap: () {},
                  ),
                  ChipRow<String>(
                    padding: const EdgeInsets.all(Space.m),
                    options: const [
                      ChipOption('cash', 'מזומן'),
                      ChipOption('bank', 'העברה / ביט'),
                      ChipOption('card', 'אשראי'),
                    ],
                    selected: 'bank',
                    onSelected: (_) {},
                  ),
                  Align(
                    alignment: AlignmentDirectional.centerStart,
                    child: TextButton(
                      onPressed: () {},
                      child: const Text(ComposeHe.moreDetails),
                    ),
                  ),
                ],
              ),
            ),
          ),
          section(
            'AmountDisplay + Keypad',
            Column(
              children: [
                AmountDisplay(keypadText: _keypad),
                Keypad(
                  onKey: (k) =>
                      setState(() => _keypad = keypadApply(_keypad, k)),
                ),
              ],
            ),
          ),
          section(
            'PrimaryButton',
            BottomActionArea(
              note:
                  'מסמך מ-${moneyInline(BigInt.from(500000))} כולל מע״מ דורש אישור',
              child: PrimaryButton(
                label: ComposeHe.issueAndWhatsApp,
                offline: _offline,
                onPressed: () {},
              ),
            ),
          ),
          section(
            'PrimaryButton · טעינה',
            pad(
              PrimaryButton(
                label: CommonHe.issue,
                loadingText: ComposeHe.stepSigning,
                onPressed: () {},
              ),
            ),
          ),
          section(
            'PrimaryButton · הרסני',
            pad(
              PrimaryButton(
                label: DocumentHe.issueCredit,
                destructive: true,
                onPressed: () {},
              ),
            ),
          ),
          section('Skeleton', const SkeletonList(rows: 3)),
          section(
            'EmptyState',
            EmptyState(
              icon: Iconsax.profile_2user,
              title: 'עוד אין לקוחות',
              message: 'הוסף מאנשי הקשר',
              actionLabel: 'הוסף לקוח',
              onAction: () {},
            ),
          ),
        ],
      ),
    );
  }
}

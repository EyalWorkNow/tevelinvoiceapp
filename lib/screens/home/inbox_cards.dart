// "לטיפול" cards (§6.H.1): words, icon, tone and the ONE embedded action of
// each kind. Shared by H and L (chip "לטיפול"). Squad A.

import 'dart:async';

import 'package:flutter/material.dart';

import '../../ui/widgets/notch_notice.dart';
import '../../api/client.dart';
import '../../api/inbox_api.dart';
import '../../api/models/models.dart';
import '../../api/settings_api.dart' show sendWebHandoff;
import '../../router.dart';
import '../../state/business_context.dart';
import '../../state/caps.dart';
import '../../ui/ds.dart';
import '../../util/labels/common_he.dart';
import '../../util/labels/inbox_he.dart';
import 'package:iconsax_flutter/iconsax_flutter.dart';
import 'doc_rows.dart' show docSubtitle;
import '../document/dialogs.dart' show askSigningPassphrase;

String inboxTitle(InboxItem c) => switch (c.kind) {
  InboxKind.approvalNeeded => InboxHe.approvalNeeded(c.count),
  InboxKind.myRejected =>
    c.count == 1
        ? InboxHe.myRejected(c.customerName, c.reason ?? '')
        : InboxHe.myRejectedMany(c.count),
  InboxKind.taxInvoiceDue =>
    c.count == 1
        ? InboxHe.taxInvoiceDue(c.customerName, _shortDate(c.dueDate))
        : InboxHe.taxInvoiceDueMany(c.count),
  InboxKind.allocationProblem =>
    c.count == 1
        ? InboxHe.allocationProblem(
            c.documentNumber == null ? null : ltrIsolate(c.documentNumber!),
          )
        : InboxHe.allocationProblemMany(c.count),
  InboxKind.signingLocked => InboxHe.signingLocked(c.count),
  InboxKind.unfinished =>
    c.count == 1
        ? InboxHe.unfinished(c.customerName)
        : InboxHe.unfinishedMany(c.count),
  InboxKind.overdue => InboxHe.overdue(c.count),
  InboxKind.quoteAccepted => InboxHe.quoteAccepted(c.customerName),
  InboxKind.expenseReview => InboxHe.expenseReview(c.count),
  InboxKind.paymentReceived => InboxHe.paymentReceived(c.customerName),
  InboxKind.shaamRenew => InboxHe.shaamRenew(c.daysLeft ?? 0),
  InboxKind.setup => switch (c.setupStep) {
    SetupStep.recoveryCodes => InboxHe.setupRecoveryCodes,
    SetupStep.logo => InboxHe.setupLogo,
    SetupStep.paymentLink => InboxHe.setupPaymentLink,
    SetupStep.team || null => InboxHe.setupTeam,
  },
  InboxKind.reportReady => InboxHe.reportReady,
  InboxKind.continuityGap => InboxHe.continuityGap,
};

String inboxActionLabel(InboxItem c) => switch (c.kind) {
  InboxKind.approvalNeeded => InboxHe.actOpen,
  InboxKind.myRejected => InboxHe.actFix,
  InboxKind.taxInvoiceDue => InboxHe.actIssue,
  InboxKind.allocationProblem => InboxHe.actRetry,
  InboxKind.signingLocked => InboxHe.actSign,
  InboxKind.unfinished => InboxHe.actContinue,
  InboxKind.overdue => InboxHe.actSendReminders,
  InboxKind.quoteAccepted => InboxHe.actConvert,
  InboxKind.expenseReview => InboxHe.actReview,
  InboxKind.paymentReceived => InboxHe.actIssueReceipt,
  InboxKind.shaamRenew => InboxHe.actRenew,
  InboxKind.setup => InboxHe.actAdd,
  InboxKind.reportReady => InboxHe.actSend,
  InboxKind.continuityGap => InboxHe.actOpen,
};

IconData inboxIcon(InboxKind k) => switch (k) {
  InboxKind.approvalNeeded => Iconsax.user_tick,
  InboxKind.myRejected => Iconsax.rotate_left,
  InboxKind.taxInvoiceDue => Iconsax.receipt_item,
  InboxKind.allocationProblem => Iconsax.bank,
  InboxKind.signingLocked => Iconsax.edit_2,
  InboxKind.unfinished => Iconsax.note_text,
  InboxKind.overdue => Iconsax.clock,
  InboxKind.quoteAccepted => Iconsax.like_1,
  InboxKind.expenseReview => Iconsax.receipt,
  InboxKind.paymentReceived => Iconsax.moneys,
  InboxKind.shaamRenew => Iconsax.link,
  InboxKind.setup => Iconsax.magicpen,
  InboxKind.reportReady => Iconsax.status_up,
  InboxKind.continuityGap => Iconsax.warning_2,
};

InboxTone inboxTone(InboxKind k) => switch (k) {
  InboxKind.myRejected ||
  InboxKind.taxInvoiceDue ||
  InboxKind.allocationProblem ||
  InboxKind.overdue ||
  InboxKind.continuityGap => InboxTone.danger,
  InboxKind.approvalNeeded ||
  InboxKind.signingLocked ||
  InboxKind.unfinished ||
  InboxKind.expenseReview ||
  InboxKind.shaamRenew => InboxTone.attention,
  _ => InboxTone.neutral,
};

/// Simpler icons and tones for the compact three-row home summary.
IconData inboxSummaryIcon(InboxKind k) => switch (k) {
  InboxKind.approvalNeeded => Icons.inventory_2_outlined,
  InboxKind.unfinished => Icons.thumb_up_outlined,
  InboxKind.overdue => Icons.timer_outlined,
  _ => inboxIcon(k),
};

InboxTone inboxSummaryTone(InboxKind k) => switch (k) {
  InboxKind.approvalNeeded => InboxTone.neutral,
  InboxKind.unfinished => InboxTone.attention,
  InboxKind.overdue ||
  InboxKind.myRejected ||
  InboxKind.taxInvoiceDue => InboxTone.danger,
  _ => inboxTone(k),
};

String? _shortDate(String? iso) {
  final d = DateTime.tryParse(iso ?? '');
  return d == null ? null : '${d.day}/${d.month}';
}

/// 'TYPE:305' for the Composer (squad B's intent string).
String typeIntent(String? documentType) {
  final code = docTypeCodes[documentType];
  return code == null ? 'REQUEST' : 'TYPE:$code';
}

/// The card widget. [onChanged] reloads the list after an in-place action.
Widget inboxCardFor(
  BuildContext context,
  InboxItem c, {
  required VoidCallback onChanged,
}) {
  final money = businessContext.can(Cap.moneyView);
  return InboxCard(
    key: Key('inbox-${c.kind.wire}'),
    icon: inboxIcon(c.kind),
    tone: inboxTone(c.kind),
    title: inboxTitle(c),
    // A ₪0 line says nothing (EXPENSE_REVIEW sends 0 for unread receipts).
    amountMinor: money && c.amountMinor != BigInt.zero ? c.amountMinor : null,
    actionLabel: inboxActionLabel(c),
    onAction: () => unawaited(runInboxAction(context, c, onChanged: onChanged)),
    onDismiss: c.kind == InboxKind.setup && c.setupStep != null
        ? () async {
            await dismissSetup(c.setupStep!);
            onChanged();
          }
        : null,
  );
}

/// The embedded action of §6.H.1 (one tap).
Future<void> runInboxAction(
  BuildContext context,
  InboxItem c, {
  required VoidCallback onChanged,
}) async {
  final first = c.documentIds.isEmpty ? null : c.documentIds.first;
  switch (c.kind) {
    case InboxKind.approvalNeeded:
      if (c.count == 1 && first != null) return openDocument(context, first);
      return openActivity(context, chip: 'inbox');
    case InboxKind.myRejected:
    case InboxKind.unfinished:
      if (c.count == 1 && first != null) {
        return openCompose(
          context,
          intent: typeIntent(c.documentType),
          draftId: first,
        );
      }
      if (c.count == 1) {
        return openCompose(
          context,
          intent: 'REQUEST',
        ); // local journal (B resumes)
      }
      return openActivity(context, chip: 'drafts');
    case InboxKind.taxInvoiceDue:
      return openCompose(context, intent: 'TYPE:305', fromDocId: first);
    case InboxKind.signingLocked:
      return _signAll(context, c, onChanged);
    case InboxKind.paymentReceived:
      // BE-28b (P3): D shows the receipt action (squad C).
      if (first != null) return openDocument(context, first);
      return;
    case InboxKind.allocationProblem:
      return _retryAllocation(context, c, onChanged);
    case InboxKind.overdue:
      return runReminders(context, onChanged: onChanged);
    case InboxKind.quoteAccepted:
      return openCompose(context, intent: 'TYPE:305', fromQuoteId: first);
    case InboxKind.expenseReview:
      return openExpenses(
        context,
        expenseId: c.count == 1 && c.expenseIds.isNotEmpty
            ? c.expenseIds.first
            : null,
      );
    case InboxKind.shaamRenew:
      return _continueOnComputer(context);
    case InboxKind.setup:
      return openBusinessSection(context, switch (c.setupStep) {
        SetupStep.recoveryCodes => BusinessSection.account,
        SetupStep.logo => BusinessSection.branding,
        SetupStep.paymentLink => BusinessSection.profile,
        SetupStep.team || null => BusinessSection.team,
      });
    case InboxKind.reportReady:
    case InboxKind.continuityGap:
      return openReports(context);
  }
}

void _toast(BuildContext context, String text, {SnackBarAction? action, NoticeMotion motion = NoticeMotion.saved}) {
  if (!context.mounted) return;
  ScaffoldMessenger.of(context)
    ..hideCurrentNotchNotice()
    ..showNotchNotice(SnackBar(content: Text(text), action: action), motion: motion);
}

Future<void> _retryAllocation(
  BuildContext context,
  InboxItem c,
  VoidCallback onChanged,
) async {
  try {
    await retryAllocation(c.documentIds);
    if (context.mounted) _toast(context, InboxHe.allocationRetried);
  } on ApiException catch (e) {
    if (context.mounted) _toast(context, e.messageHe, motion: NoticeMotion.error);
  }
  onChanged();
}

/// SIGNING_LOCKED "חתום": release once (Face ID / passphrase), sign every
/// waiting original in place (§6.H.1, F7).
Future<void> _signAll(
  BuildContext context,
  InboxItem c,
  VoidCallback onChanged,
) async {
  try {
    final signed = await signPendingDocuments(
      c.documentIds,
      askPassphrase: () async {
        if (!context.mounted) return null;
        return askSigningPassphrase(context);
      },
    );
    if (signed > 0 && context.mounted) {
      _toast(context, InboxHe.signedDone(signed), motion: NoticeMotion.signed);
    }
  } on ApiException catch (e) {
    if (context.mounted) _toast(context, e.messageHe, motion: NoticeMotion.error);
  }
  onChanged();
}

/// SHAAM_RENEW "המשך במחשב": BE-35 e-mails the link (one tap; P2 OAuth is BE-42).
Future<void> _continueOnComputer(BuildContext context) async {
  try {
    await sendWebHandoff('TAX_AUTHORITY', InboxHe.handoffShaam);
    if (context.mounted) _toast(context, InboxHe.handoffSent, motion: NoticeMotion.sent);
  } on ApiException catch (e) {
    if (context.mounted) _toast(context, e.messageHe, motion: NoticeMotion.error);
  }
}

/// J10 (§9.3) + 0.8: the tap opens a preview of the overdue invoices; nothing
/// is sent before the explicit confirm, and only to the rows left checked.
/// Customers without e-mail / consent are offered WhatsApp, one tap each.
Future<void> runReminders(
  BuildContext context, {
  required VoidCallback onChanged,
}) async {
  final List<DocumentSummary> overdue;
  try {
    overdue = await fetchOverdueDocuments();
  } on ApiException catch (e) {
    if (context.mounted) _toast(context, e.messageHe, motion: NoticeMotion.error);
    return;
  }
  if (!context.mounted) return;
  if (overdue.isEmpty) {
    _toast(context, InboxHe.remindersNone);
    onChanged();
    return;
  }
  final chosen = await showReminderPreview(context, overdue);
  if (chosen == null || chosen.isEmpty || !context.mounted) return;
  _toast(context, InboxHe.remindersSending, motion: NoticeMotion.reminder);
  final profile = businessContext.profile;
  final ReminderResult result;
  try {
    result = await sendReminders(
      paymentUrl: profile?.paymentLinkUrl,
      only: chosen,
    );
  } on ApiException catch (e) {
    if (context.mounted) _toast(context, e.messageHe, motion: NoticeMotion.error);
    return;
  }
  if (!context.mounted) return;
  _toast(
    context,
    InboxHe.remindersDone(result.sent, result.whatsapp.length),
    motion: NoticeMotion.reminder,
    action: result.whatsapp.isEmpty
        ? null
        : SnackBarAction(
            label: InboxHe.remindersWhatsApp,
            onPressed: () =>
                unawaited(showWhatsAppReminders(context, result.whatsapp)),
          ),
  );
  onChanged();
}

/// The "באיחור" preview: every overdue invoice, checked by default. Returns
/// the ids to remind, or null when the user cancels.
Future<Set<String>?> showReminderPreview(
  BuildContext context,
  List<DocumentSummary> overdue,
) {
  final chosen = {for (final d in overdue) d.id};
  return showDialog<Set<String>>(
    context: context,
    builder: (dialogContext) => StatefulBuilder(
      builder: (dialogContext, setState) => AlertDialog(
        key: const Key('reminders-preview'),
        title: const Text(InboxHe.remindersPreviewTitle),
        content: SizedBox(
          width: double.maxFinite,
          child: ListView(
            shrinkWrap: true,
            children: [
              Text(InboxHe.remindersPreviewBody, style: AppText.secondary),
              const SizedBox(height: Space.s),
              for (final d in overdue)
                CheckboxListTile(
                  key: Key('reminder-${d.id}'),
                  contentPadding: EdgeInsets.zero,
                  value: chosen.contains(d.id),
                  onChanged: (on) => setState(() {
                    on == true ? chosen.add(d.id) : chosen.remove(d.id);
                  }),
                  title: Text(
                    d.customerName == null || d.customerName!.isEmpty
                        ? InboxHe.noCustomer
                        : d.customerName!,
                  ),
                  subtitle: Text(docSubtitle(d)),
                  secondary: AmountText(d.openMinor ?? d.totalMinor),
                ),
            ],
          ),
        ),
        actions: [
          TextButton(
            key: const Key('reminders-cancel'),
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text(InboxHe.remindersCancel),
          ),
          FilledButton(
            key: const Key('reminders-confirm'),
            onPressed: chosen.isEmpty
                ? null
                : () => Navigator.of(dialogContext).pop({...chosen}),
            child: Text(InboxHe.remindersConfirm(chosen.length)),
          ),
        ],
      ),
    ),
  );
}

/// The WhatsApp list (a system dialog, not a sheet — F4).
Future<void> showWhatsAppReminders(
  BuildContext context,
  List<ReminderTarget> targets,
) => showDialog<void>(
  context: context,
  builder: (dialogContext) => AlertDialog(
    title: const Text(InboxHe.remindersWhatsAppTitle),
    content: SizedBox(
      width: double.maxFinite,
      child: ListView(
        shrinkWrap: true,
        children: [
          for (final t in targets)
            ListTile(
              key: Key('wa-${t.documentId}'),
              contentPadding: EdgeInsets.zero,
              title: Text(t.customerName ?? InboxHe.noCustomer),
              subtitle: AmountText(t.openMinor),
              trailing: TextButton(
                onPressed: () async {
                  try {
                    await remindOnWhatsApp(
                      t,
                      businessName: businessContext.displayName,
                      paymentUrl: businessContext.profile?.paymentLinkUrl,
                    );
                  } on ApiException catch (e) {
                    if (dialogContext.mounted) {
                      _toast(dialogContext, e.messageHe, motion: NoticeMotion.error);
                    }
                  }
                },
                child: const Text(InboxHe.remindersWhatsApp),
              ),
            ),
        ],
      ),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.of(dialogContext).pop(),
        child: const Text(CommonHe.close),
      ),
    ],
  ),
);

// "אין לך חשבון? דברו איתנו" (owner 2026-11-18): Tevel opens every account
// itself after a short conversation, so instead of a sign-up the app offers
// WhatsApp (prefilled message) or e-mail to the Tevel team.

import 'package:flutter/material.dart';
import 'package:iconsax_flutter/iconsax_flutter.dart';

import '../../ui/theme.dart';
import '../../ui/widgets/big_button.dart';
import '../../ui/widgets/sheet.dart';
import '../../util/allowed_urls.dart';
import '../../util/labels/labels.dart';

/// The link under the sign-in button.
class NoAccountCta extends StatelessWidget {
  const NoAccountCta({super.key});

  @override
  Widget build(BuildContext context) => Center(
    child: TextButton(
      key: const Key('no-account-cta'),
      style: TextButton.styleFrom(minimumSize: const Size(Hit.min, Hit.min)),
      onPressed: () => showContactTevelSheet(context),
      child: const Text(AuthHe.noAccount),
    ),
  );
}

/// WhatsApp / e-mail to the Tevel team, with one line on how accounts open.
Future<void> showContactTevelSheet(BuildContext context) => showAppSheet<void>(
  context,
  builder: (sheet) {
    final p = sheet.palette;
    return Column(
      key: const Key('contact-tevel-sheet'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Icon(Iconsax.messages_2, size: 48, color: p.info),
        const SizedBox(height: Space.l),
        const SheetTitle(AuthHe.contactTitle, subtitle: AuthHe.contactBody),
        BigButton(
          key: const Key('contact-whatsapp'),
          label: AuthHe.contactWhatsApp,
          icon: Iconsax.message,
          variant: BigButtonVariant.whatsapp,
          onPressed: () => launchAllowed(tevelWhatsAppUri()),
        ),
        const SizedBox(height: Space.m),
        BigButton(
          key: const Key('contact-email'),
          label: AuthHe.contactEmail,
          icon: Iconsax.sms,
          variant: BigButtonVariant.secondary,
          onPressed: () => launchAllowed(tevelEmailUri()),
        ),
        const SizedBox(height: Space.m),
        Text(
          '$tevelPhone · $tevelEmail',
          textDirection: TextDirection.ltr,
          textAlign: TextAlign.center,
          style: AppText.caption.copyWith(color: p.muted),
        ),
      ],
    );
  },
);

import 'package:flutter/material.dart';

import '../../api/business_registration_api.dart';
import '../../api/client.dart';
import '../../api/reports_api.dart';
import '../../state/cache.dart';
import '../../state/customer_crm_store.dart';
import '../../state/session.dart';
import '../../ui/ds.dart';
import 'business_template.dart';

class BusinessDataPage extends StatefulWidget {
  const BusinessDataPage({super.key});
  @override
  State<BusinessDataPage> createState() => _BusinessDataPageState();
}

class _BusinessDataPageState extends State<BusinessDataPage> {
  Map<String, dynamic>? _registration;
  Object? _error;
  bool _loading = true;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final business = session.business?.businessId;
    try {
      final registration = await fetchBusinessRegistration();
      if (mounted && business == session.business?.businessId) {
        setState(() {
          _registration = registration;
          _error = null;
        });
      }
    } on Object catch (error) {
      if (mounted) setState(() => _error = error);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _download({bool archive = false}) async {
    if (_busy) return;
    final business = session.business?.businessId;
    if (business == null) return;
    setState(() => _busy = true);
    try {
      if (archive) {
        final crm = CustomerCrmStore.instance;
        await crm.loadForBusiness(business);
        await crm.sync();
        if (crm.pendingCount != 0 ||
            !crm.readyForEdits ||
            await AppCache.hasPending()) {
          throw const BusinessRegistrationInputException(
            'יש פעולות במכשיר שטרם הושלמו או סונכרנו. השלימו אותן לפני ייצוא מלא.',
          );
        }
      }
      if (!mounted ||
          ModalRoute.of(context)?.isCurrent != true ||
          business != session.business?.businessId) {
        return;
      }
      final cert = _registration?['certificate'] as Map<String, dynamic>?;
      final file = archive
          ? await exportBusinessArchive()
          : await downloadBusinessCertificate(
              cert!['filename'] as String,
              cert['mimeType'] as String,
            );
      if (!mounted ||
          ModalRoute.of(context)?.isCurrent != true ||
          business != session.business?.businessId) {
        return;
      }
      await fileSharer(file);
    } on Object catch (error) {
      if (mounted) {
        if (error is BusinessRegistrationInputException) {
          ScaffoldMessenger.of(
            context,
          ).showSnackBar(SnackBar(content: Text(error.message)));
        } else {
          showErrorSnack(context, error);
        }
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => BusinessPage(
    title: 'פרטי ההרשמה וייצוא',
    children: [
      Text(session.account?.displayName ?? '', style: AppText.title),
      const SizedBox(height: Space.s),
      Text(session.profile?.legalName ?? '', style: AppText.headline),
      Text(session.profile?.taxId ?? '', style: AppText.body),
      Text(session.profile?.email ?? '', style: AppText.body),
      Text(session.profile?.phone ?? '', style: AppText.body),
      const SizedBox(height: Space.l),
      if (_loading) const LinearProgressIndicator(),
      if (_error != null) ...[
        Text(
          _error is ApiException && (_error as ApiException).status == 404
              ? 'פרטי ההרשמה המורחבים עדיין לא זמינים לחשבון הזה.'
              : errorTextHe(_error!),
          style: AppText.body,
        ),
        TextButton(onPressed: _load, child: const Text('נסה שוב')),
      ],
      if (_registration?['certificate'] case final Map certificate)
        ListTile(
          title: const Text('תעודת העסק'),
          subtitle: Text(certificate['filename'] as String),
          leading: const Icon(Icons.description_outlined),
          onTap: _busy || session.offline ? null : _download,
        ),
      const SizedBox(height: Space.xl),
      const Text('ייצוא מלא של העסק', style: AppText.title),
      const SizedBox(height: Space.s),
      const Text(
        'קובץ ZIP לכל התאריכים: הכנסות, הוצאות וקבצי המקור, לקוחות, ספקים, הצעות מחיר, ניהול לקוחות ויומן פעולות. כולל חוברת Excel וקובצי נתונים מסודרים.',
        style: AppText.body,
      ),
      const SizedBox(height: Space.m),
      if (_busy) const LinearProgressIndicator(),
      FilledButton.icon(
        key: const Key('export-business-archive'),
        onPressed: _busy || session.offline
            ? null
            : () => _download(archive: true),
        icon: const Icon(Icons.folder_zip_outlined),
        label: Text(_busy ? 'מכין קובץ…' : 'הורדת כל התוכן כ־ZIP'),
      ),
    ],
  );
}

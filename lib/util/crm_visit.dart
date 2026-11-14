import 'package:intl/intl.dart' show DateFormat;

import '../state/customer_crm_store.dart';
import 'phone.dart';

/// Customer-facing appointment details only; never include private notes or costs.
Uri? crmVisitMessageUri(CustomerCrmJob job, String? phone) {
  final number = waPhone(phone);
  if (number == null) return null;
  final date = DateFormat('dd.MM.yyyy').format(job.scheduledAt);
  final time = DateFormat('HH:mm').format(job.scheduledAt);
  final text = [
    'שלום ${job.customerName},',
    'לתיאום הביקור: ${job.title}',
    '$date בשעה $time',
    if (job.address.isNotEmpty) 'כתובת: ${job.address}',
    'האם המועד מתאים?',
  ].join('\n');
  return Uri.https('wa.me', '/$number', {'text': text});
}

Uri? crmVisitMapUri(CustomerCrmJob job) => job.address.trim().isEmpty
    ? null
    : Uri.https('maps.apple.com', '/', {'q': job.address.trim()});

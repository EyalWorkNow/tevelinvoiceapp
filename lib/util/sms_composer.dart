import 'package:flutter/services.dart';

/// The operating system presents the message; the user explicitly sends or cancels it.
typedef SmsComposer = Future<String> Function(String phone, String body);
SmsComposer smsComposer = (phone, body) async =>
    await const MethodChannel(
      'tevel/sms_composer',
    ).invokeMethod<String>('compose', {'phone': phone, 'body': body}) ??
    'CANCELLED';

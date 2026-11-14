// Israeli phone → WhatsApp (wa.me) international digits.

/// '050-123-4567' / '+972 50 1234567' / '00972501234567' / '501234567'
/// → '972501234567'. Other international numbers written with '+' or '00'
/// are kept as digits ('+1 415 555 0100' → '14155550100').
/// Returns null when the text is not a usable phone number.
String? waPhone(String? raw) {
  if (raw == null) return null;
  final trimmed = raw.trim();
  if (trimmed.isEmpty) return null;
  final international = trimmed.startsWith('+') || trimmed.startsWith('00');
  var digits = trimmed.replaceAll(RegExp(r'\D'), '');
  if (digits.startsWith('00')) digits = digits.substring(2);

  if (digits.startsWith('972')) {
    var national = digits.substring(3);
    if (national.startsWith('0')) {
      national = national.substring(1); // +972 (0)50…
    }
    return _validIsraeli(national) ? '972$national' : null;
  }
  if (international) {
    return digits.length >= 8 && digits.length <= 15 ? digits : null;
  }
  final national = digits.startsWith('0') ? digits.substring(1) : digits;
  return _validIsraeli(national) ? '972$national' : null;
}

/// National number without the leading 0: mobiles are 9 digits (5X…),
/// landlines 8 digits (2/3/4/8/9 + 7) and 7X VoIP lines 9 digits.
bool _validIsraeli(String national) =>
    RegExp(r'^(5\d{8}|7\d{8}|[2-489]\d{7})$').hasMatch(national);

/// wa.me link: a chat with [phone] (already from [waPhone]) or, without a
/// number, WhatsApp's own contact picker with the [text] pre-filled.
Uri whatsAppUri({String? phone, required String text}) =>
    Uri.parse('https://wa.me/${phone ?? ''}?text=${Uri.encodeComponent(text)}');

/// Israeli display format: '0521807547' → '052-1807547'.
String formatPhoneHe(String? raw) {
  if (raw == null || raw.isEmpty) return '';
  if (raw.contains('-')) return raw;
  var d = raw.replaceAll(RegExp(r'\D'), '');
  if (d.startsWith('972')) d = '0${d.substring(3)}';
  if (d.length == 10 && d.startsWith('05')) {
    return '${d.substring(0, 3)}-${d.substring(3)}';
  }
  if (d.length == 9 &&
      (d.startsWith('02') ||
          d.startsWith('03') ||
          d.startsWith('04') ||
          d.startsWith('08') ||
          d.startsWith('09') ||
          d.startsWith('07'))) {
    return '${d.substring(0, 2)}-${d.substring(2)}';
  }
  return raw;
}

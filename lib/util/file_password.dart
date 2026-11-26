// §7 "קובץ מוגן בסיסמה": the password the app sets for one protected send.
// 8 characters, capitals and digits only, never 0/O, 1/I/L (they read
// alike). The server checks the same alphabet (packages/postgres
// protected-files.ts FILE_PASSWORD_ALPHABET).

import 'dart:math';

const filePasswordAlphabet = 'ABCDEFGHJKMNPQRSTUVWXYZ23456789';
const filePasswordLength = 8;

final _shape = RegExp('^[$filePasswordAlphabet]{$filePasswordLength}\$');

/// A new random password (one per send). [random] only for tests.
String generateFilePassword([Random? random]) {
  final r = random ?? Random.secure();
  return List.generate(
    filePasswordLength,
    (_) => filePasswordAlphabet[r.nextInt(filePasswordAlphabet.length)],
  ).join();
}

bool isValidFilePassword(String value) => _shape.hasMatch(value);

/// Big-letters display: two groups of four ("K7M4 Q9P2"). The copy button
/// and the messages always carry the plain 8 characters.
String displayFilePassword(String password) => password.length == 8
    ? '${password.substring(0, 4)} ${password.substring(4)}'
    : password;

import 'dart:math';

final _random = Random.secure();

// No 0/o/1/l/i so ids survive being read aloud or copied by hand.
const _idAlphabet = '23456789abcdefghjkmnpqrstuvwxyz';

/// A short random id for shelves and items.
String newId([int length = 10]) {
  final buffer = StringBuffer();
  for (var i = 0; i < length; i++) {
    buffer.write(_idAlphabet[_random.nextInt(_idAlphabet.length)]);
  }
  return buffer.toString();
}

final _idPattern = RegExp('^[$_idAlphabet]{6,24}\$');

bool isValidId(String value) => _idPattern.hasMatch(value);

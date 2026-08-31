/// Mirrors the server's rules in Common/Validation/UsernameValidator.cs.
/// Keep these in sync; anything stricter locks out accounts the server accepts.
const int usernameMinLength = 3;
const int usernameMaxLength = 32;

final RegExp _emailPattern = RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$');

/// Control and zero-width characters, which the server rejects as obnoxious.
final RegExp _obnoxiousCharacters = RegExp(
  r'[\u0000-\u001F\u007F\u200B-\u200F\u2060\uFEFF]',
);

/// Validates the login identifier, which may be a username or an email.
///
/// An `@` means it can only be an email: the server refuses usernames that
/// contain one.
String? validateUsernameOrEmail(String? value) {
  final input = (value ?? '').trim();

  if (input.isEmpty) return 'Please enter your username or email';

  if (input.contains('@')) {
    return _emailPattern.hasMatch(input) ? null : 'Enter a valid email address';
  }

  if (input.length < usernameMinLength) {
    return 'Usernames are at least $usernameMinLength characters';
  }

  if (input.length > usernameMaxLength) {
    return 'Usernames are at most $usernameMaxLength characters';
  }

  if (_obnoxiousCharacters.hasMatch(input)) {
    return 'Usernames cannot contain invisible or control characters';
  }

  return null;
}

/// Validates a password field. Strength rules are the server's to enforce.
String? validatePassword(String? value) {
  if ((value ?? '').isEmpty) return 'Please enter your password';
  return null;
}

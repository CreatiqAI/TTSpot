import 'package:supabase_flutter/supabase_flutter.dart';

/// Throw this from repositories/controllers when you already have a
/// human-readable message for the user.
class AppException implements Exception {
  const AppException(this.message);
  final String message;
  @override
  String toString() => message;
}

/// Turns any thrown object into a short sentence safe to show in a SnackBar.
String friendlyError(Object error) {
  if (error is AppException) return error.message;

  if (error is AuthException) {
    switch (error.code) {
      case 'invalid_credentials':
        return 'Wrong email or password.';
      case 'user_already_exists':
      case 'email_exists':
        return 'That email already has an account. Try signing in.';
      case 'weak_password':
        return 'Password is too weak. Use at least 6 characters.';
      case 'email_not_confirmed':
        return 'Check your inbox and confirm your email first.';
      case 'over_email_send_rate_limit':
      case 'over_request_rate_limit':
        return 'Too many attempts. Wait a minute and try again.';
      case 'validation_failed':
        return 'That doesn\'t look like a valid email.';
    }
    return error.message;
  }

  if (error is PostgrestException) {
    if (error.message.contains('Event is full')) return 'This meet is full.';
    if (error.code == '23505') return 'Already done.';
    if (error.code == '23514') return 'One of the fields has an invalid value.';
    if (error.code == '42501') return 'You don\'t have permission to do that.';
    return error.message;
  }

  if (error is StorageException) {
    if (error.statusCode == '413') return 'That photo is too large. Pick a smaller one.';
    return 'Upload failed: ${error.message}';
  }

  final text = error.toString();
  if (text.contains('SocketException') || text.contains('Failed host lookup')) {
    return 'No internet connection.';
  }
  return 'Something went wrong. Please try again.';
}

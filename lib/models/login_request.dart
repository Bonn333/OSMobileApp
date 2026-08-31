/// Request body for `POST /2/account/login`.
///
/// The v1 endpoint (`POST /1/account/login`, body `{email, password}`) is
/// retired and answers 410 Gone. v2 renames `email` to `usernameOrEmail` and
/// requires a Cloudflare Turnstile token: the server rejects the request with
/// 400 when [turnstileResponse] is absent, null or empty, and with
/// 403 `Turnstile.Invalid` when the value does not verify.
class LoginRequest {
  final String usernameOrEmail;
  final String password;
  final String turnstileResponse;

  LoginRequest({
    required this.usernameOrEmail,
    required this.password,
    required this.turnstileResponse,
  });

  Map<String, dynamic> toJson() {
    return {
      'usernameOrEmail': usernameOrEmail,
      'password': password,
      'turnstileResponse': turnstileResponse,
    };
  }
}

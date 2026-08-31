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

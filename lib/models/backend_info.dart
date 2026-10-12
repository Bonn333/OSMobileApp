/// Response of `GET /1`.
class BackendInfo {
  final String version;
  final String? frontendUrl;

  /// Null when the instance has Turnstile disabled.
  final String? turnstileSiteKey;

  /// Provider keys such as `discord` or `google`.
  final List<String> oAuthProviders;

  const BackendInfo({
    required this.version,
    this.frontendUrl,
    this.turnstileSiteKey,
    this.oAuthProviders = const [],
  });

  bool get isTurnstileEnabled =>
      turnstileSiteKey != null && turnstileSiteKey!.isNotEmpty;

  /// The OAuth flow ends on frontend pages, so it needs the frontend URL.
  bool get isOAuthAvailable => oAuthProviders.isNotEmpty && frontendUrl != null;

  factory BackendInfo.fromJson(Map<String, dynamic> json) {
    final siteKey = json['turnstileSiteKey'] as String?;
    final providers = json['oAuthProviders'];
    final frontendUrl = json['frontendUrl'] as String?;

    return BackendInfo(
      version: json['version'] as String? ?? 'unknown',
      frontendUrl: (frontendUrl == null || frontendUrl.isEmpty)
          ? null
          : frontendUrl,
      turnstileSiteKey: (siteKey == null || siteKey.isEmpty) ? null : siteKey,
      oAuthProviders: providers is List
          ? providers.whereType<String>().where((p) => p.isNotEmpty).toList()
          : const [],
    );
  }
}

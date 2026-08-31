/// Response of `GET /1`.
class BackendInfo {
  final String version;
  final String? frontendUrl;

  /// Null when the instance has Turnstile disabled.
  final String? turnstileSiteKey;

  const BackendInfo({
    required this.version,
    this.frontendUrl,
    this.turnstileSiteKey,
  });

  bool get isTurnstileEnabled =>
      turnstileSiteKey != null && turnstileSiteKey!.isNotEmpty;

  factory BackendInfo.fromJson(Map<String, dynamic> json) {
    final siteKey = json['turnstileSiteKey'] as String?;

    return BackendInfo(
      version: json['version'] as String? ?? 'unknown',
      frontendUrl: json['frontendUrl'] as String?,
      turnstileSiteKey: (siteKey == null || siteKey.isEmpty) ? null : siteKey,
    );
  }
}

/// Response of `GET /1`, the unauthenticated metadata endpoint.
///
/// This is how a client discovers the Cloudflare Turnstile site key rather than
/// hardcoding it, which also makes self-hosted instances work: they publish
/// their own key, or none at all when Turnstile is switched off.
class BackendInfo {
  final String version;
  final String? frontendUrl;

  /// Null or empty when the instance has Turnstile disabled. The official
  /// frontend treats that as "no challenge required" and posts a placeholder.
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

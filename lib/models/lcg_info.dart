/// Response of `GET /2/devices/{deviceId}/lcg`.
class LcgInfo {
  final String host;
  final int port;
  final String pathPrefix;
  final String country;

  const LcgInfo({
    required this.host,
    required this.port,
    required this.pathPrefix,
    required this.country,
  });

  factory LcgInfo.fromJson(Map<String, dynamic> json) {
    return LcgInfo(
      host: json['host'] as String,
      port: (json['port'] as num?)?.toInt() ?? 443,
      pathPrefix: json['pathPrefix'] as String? ?? '',
      country: json['country'] as String? ?? '',
    );
  }

  /// The gateway owns host, port and path prefix; the route is the client's.
  Uri liveSocketUri(String hubId) {
    final prefix = pathPrefix.endsWith('/')
        ? pathPrefix.substring(0, pathPrefix.length - 1)
        : pathPrefix;

    return Uri(
      scheme: port == 80 ? 'ws' : 'wss',
      host: host,
      port: (port == 80 || port == 443) ? null : port,
      path: '$prefix/1/ws/live/$hubId',
    );
  }
}

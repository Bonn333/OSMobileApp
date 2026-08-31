import 'dart:convert';

/// Model for all secure storage data (API token, cookies, etc.)
class SecureStorageData {
  final String? apiToken;
  final String? sessionCookies;

  const SecureStorageData({
    this.apiToken,
    this.sessionCookies,
  });

  factory SecureStorageData.fromJson(Map<String, dynamic> json) {
    return SecureStorageData(
      apiToken: json['apiToken'] as String?,
      sessionCookies: json['sessionCookies'] as String?,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'apiToken': apiToken,
      'sessionCookies': sessionCookies,
    };
  }

  /// Note the explicit `clear*` flags: a plain `field ?? this.field` cannot
  /// distinguish "leave unchanged" from "set to null", so without them a
  /// logout would silently keep the stored secret.
  SecureStorageData copyWith({
    String? apiToken,
    String? sessionCookies,
    bool clearApiToken = false,
    bool clearSessionCookies = false,
  }) {
    return SecureStorageData(
      apiToken: clearApiToken ? null : (apiToken ?? this.apiToken),
      sessionCookies: clearSessionCookies
          ? null
          : (sessionCookies ?? this.sessionCookies),
    );
  }

  String toJsonString() => jsonEncode(toJson());

  factory SecureStorageData.fromJsonString(String jsonString) {
    final json = jsonDecode(jsonString) as Map<String, dynamic>;
    return SecureStorageData.fromJson(json);
  }

  static SecureStorageData empty() {
    return const SecureStorageData();
  }
}

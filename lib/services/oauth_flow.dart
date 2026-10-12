import 'dart:convert';

/// Helpers for the OpenShock OAuth flow.
///
/// The API runs the flow on cookies: `POST /1/oauth/{provider}/authorize`
/// redirects to the provider, the provider calls back into the API, and the
/// API's handoff sets the session cookie and redirects to a frontend page.
/// The app follows the flow in a WebView and watches for those pages.
class OAuthFlow {
  OAuthFlow._();

  static const _providerLabels = {
    'discord': 'Discord',
    'google': 'Google',
    'twitter': 'X (Twitter)',
  };

  /// Mirrors the frontend's `oauth-errors.ts`.
  static const _errorMessages = {
    'oauthFlowNotStarted':
        'No active sign-in attempt was found. The flow may have expired, '
        'please try again.',
    'providerMismatch':
        'The sign-in attempt did not match the provider you returned from. '
        'Please try again.',
    'mustBeAnonymous':
        'You are already signed in. Sign out before starting a new sign-in '
        'attempt.',
    'emailAlreadyRegistered':
        'An account with this email already exists. Sign in to that account '
        'on the website to link this provider.',
    'internalError':
        'Something went wrong on our end. Please try again in a moment.',
    googleRejected: 'Google rejected the sign-in attempt. Please try again.',
    googleBlockedInApp:
        'Google does not allow signing in from inside apps, so it blocked '
        'this attempt.\n\n'
        'Sign in with your email and password, or with another provider, '
        'instead. If your account only uses Google, set a password first: '
        'open openshock.app in your browser, choose "Forgot password" and '
        'enter your account email.',
  };

  /// Google's own error page, not one of the frontend's codes.
  static const googleRejected = 'googleRejected';

  /// Google refuses OAuth in embedded WebViews (`disallowed_useragent`).
  static const googleBlockedInApp = 'googleBlockedInApp';

  /// Shown next to providers that may refuse to run inside the app.
  static String? providerNotice(String provider) =>
      provider.toLowerCase() == 'google'
      ? 'Google may block sign-in inside the app. If it does, use your '
            'email and password instead.'
      : null;

  static String providerLabel(String provider) =>
      _providerLabels[provider.toLowerCase()] ?? provider;

  static String errorMessage(String? code) =>
      _errorMessages[code] ?? 'Sign-in failed. Please try again.';

  /// `POST` target that starts a login (or signup) with [provider].
  static Uri authorizeUri(String apiBaseUrl, String provider) {
    final base = Uri.parse(apiBaseUrl);
    final basePath = base.path.endsWith('/')
        ? base.path.substring(0, base.path.length - 1)
        : base.path;

    return base.replace(
      path: '$basePath/1/oauth/${Uri.encodeComponent(provider)}/authorize',
      queryParameters: const {'flow': 'LoginOrCreate'},
    );
  }

  /// Decides what a navigation to [url] means for the flow.
  static OAuthStep classify(Uri url, Uri frontendUrl) {
    final host = url.host.toLowerCase();

    if (host == 'accounts.google.com' && url.path.contains('/oauth/error')) {
      return OAuthStep.failed(_googleErrorCode(url));
    }

    if (host != frontendUrl.host.toLowerCase()) {
      return const OAuthStep.proceed();
    }

    final segments = url.pathSegments.where((s) => s.isNotEmpty).toList();
    if (segments.isEmpty) return const OAuthStep.proceed();

    switch (segments.first) {
      // Handoff signed in an existing account, or signup finished.
      case 'home':
        return const OAuthStep.signedIn();
      case 'oauth' when segments.length > 1 && segments[1] == 'error':
        return OAuthStep.failed(url.queryParameters['error']);
      // Signup ends here when the new account still needs email activation,
      // and the signup page falls back here when the flow cookie is gone.
      case 'login':
        if (url.queryParameters['message'] == 'signup-success') {
          return const OAuthStep.pendingActivation();
        }
        return const OAuthStep.failed('oauthFlowNotStarted');
      // Includes `/oauth/{provider}/create`, where the user picks a username.
      default:
        return const OAuthStep.proceed();
    }
  }

  /// Google's error page carries the reason in `authError`, a base64
  /// protobuf. An unreadable reason is most likely the WebView block, as
  /// that is the error this app runs into.
  static String _googleErrorCode(Uri url) {
    final authError = url.queryParameters['authError'];
    if (authError == null || authError.isEmpty) return googleBlockedInApp;

    try {
      // A raw `+` in the query decodes to a space.
      final normalized = base64Url.normalize(
        authError
            .replaceAll(' ', '-')
            .replaceAll('+', '-')
            .replaceAll('/', '_'),
      );
      final decoded = latin1.decode(base64Url.decode(normalized));
      return decoded.contains('disallowed_useragent')
          ? googleBlockedInApp
          : googleRejected;
    } on FormatException {
      return googleBlockedInApp;
    }
  }
}

enum OAuthStepKind { proceed, signedIn, pendingActivation, failed }

class OAuthStep {
  final OAuthStepKind kind;

  /// Frontend error code, set when [kind] is [OAuthStepKind.failed].
  final String? errorCode;

  const OAuthStep.proceed() : kind = OAuthStepKind.proceed, errorCode = null;

  const OAuthStep.signedIn() : kind = OAuthStepKind.signedIn, errorCode = null;

  const OAuthStep.pendingActivation()
    : kind = OAuthStepKind.pendingActivation,
      errorCode = null;

  const OAuthStep.failed(this.errorCode) : kind = OAuthStepKind.failed;
}

/// What the OAuth screen returns. A cancelled flow returns null instead.
sealed class OAuthResult {
  const OAuthResult();
}

class OAuthSignedIn extends OAuthResult {
  final String sessionToken;

  const OAuthSignedIn(this.sessionToken);
}

class OAuthPendingActivation extends OAuthResult {
  const OAuthPendingActivation();
}

class OAuthFailed extends OAuthResult {
  final String message;

  /// Error code from [OAuthFlow], when the failure has a known cause.
  final String? code;

  const OAuthFailed(this.message, {this.code});
}

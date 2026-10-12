import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:openshock_mobile/services/oauth_flow.dart';

void main() {
  group('OAuthFlow.authorizeUri', () {
    test('builds the authorize URL for the login flow', () {
      final uri = OAuthFlow.authorizeUri(
        'https://api.openshock.app',
        'discord',
      );

      expect(
        uri.toString(),
        'https://api.openshock.app/1/oauth/discord/authorize?flow=LoginOrCreate',
      );
    });

    test('keeps a base path and drops its trailing slash', () {
      final uri = OAuthFlow.authorizeUri('https://example.com/api/', 'google');

      expect(
        uri.toString(),
        'https://example.com/api/1/oauth/google/authorize?flow=LoginOrCreate',
      );
    });
  });

  group('OAuthFlow.classify', () {
    final frontend = Uri.parse('https://openshock.app');

    OAuthStep classify(String url) =>
        OAuthFlow.classify(Uri.parse(url), frontend);

    test('lets provider and API pages load', () {
      for (final url in [
        'https://discord.com/oauth2/authorize?client_id=1',
        'https://api.openshock.app/1/oauth/discord/handoff',
        'https://home.example.com/home',
      ]) {
        expect(classify(url).kind, OAuthStepKind.proceed, reason: url);
      }
    });

    test('lets the signup page load', () {
      expect(
        classify('https://openshock.app/oauth/discord/create').kind,
        OAuthStepKind.proceed,
      );
    });

    test('treats the home page as signed in', () {
      expect(
        classify('https://openshock.app/home').kind,
        OAuthStepKind.signedIn,
      );
      expect(
        classify('https://OpenShock.app/home/').kind,
        OAuthStepKind.signedIn,
      );
    });

    test('reads the error code from the error page', () {
      final step = classify(
        'https://openshock.app/oauth/error?error=emailAlreadyRegistered',
      );

      expect(step.kind, OAuthStepKind.failed);
      expect(step.errorCode, 'emailAlreadyRegistered');
    });

    test('reports an account that still needs activation', () {
      expect(
        classify('https://openshock.app/login?message=signup-success').kind,
        OAuthStepKind.pendingActivation,
      );
    });

    test('treats a fall back to the login page as an expired flow', () {
      final step = classify('https://openshock.app/login');

      expect(step.kind, OAuthStepKind.failed);
      expect(step.errorCode, 'oauthFlowNotStarted');
    });
  });

  group('OAuthFlow.classify on Google error pages', () {
    final frontend = Uri.parse('https://openshock.app');

    // Google sends the reason as a base64 protobuf, using `+` and `/`.
    String googleError(String reason) {
      final encoded = base64.encode(
        latin1.encode('\n${String.fromCharCode(reason.length)}$reason'),
      );
      return 'https://accounts.google.com/signin/oauth/error/v2'
          '?authError=${Uri.encodeQueryComponent(encoded)}&client_id=1';
    }

    test('recognises the in-app WebView block', () {
      final step = OAuthFlow.classify(
        Uri.parse(googleError('disallowed_useragent')),
        frontend,
      );

      expect(step.kind, OAuthStepKind.failed);
      expect(step.errorCode, OAuthFlow.googleBlockedInApp);
    });

    test('reports other Google errors as a plain rejection', () {
      final step = OAuthFlow.classify(
        Uri.parse(googleError('admin_policy_enforced')),
        frontend,
      );

      expect(step.errorCode, OAuthFlow.googleRejected);
    });

    test('assumes the WebView block when the reason is unreadable', () {
      for (final url in [
        'https://accounts.google.com/signin/oauth/error',
        'https://accounts.google.com/signin/oauth/error?authError=not*base64',
      ]) {
        final step = OAuthFlow.classify(Uri.parse(url), frontend);
        expect(step.errorCode, OAuthFlow.googleBlockedInApp, reason: url);
      }
    });

    test('lets the Google sign-in pages load', () {
      final step = OAuthFlow.classify(
        Uri.parse('https://accounts.google.com/o/oauth2/v2/auth?client_id=1'),
        frontend,
      );

      expect(step.kind, OAuthStepKind.proceed);
    });

    test('explains how to get a password for a Google-only account', () {
      expect(
        OAuthFlow.errorMessage(OAuthFlow.googleBlockedInApp),
        contains('Forgot password'),
      );
      expect(OAuthFlow.providerNotice('google'), isNotNull);
      expect(OAuthFlow.providerNotice('discord'), isNull);
    });
  });

  group('OAuthFlow labels and messages', () {
    test('names known providers and passes others through', () {
      expect(OAuthFlow.providerLabel('discord'), 'Discord');
      expect(OAuthFlow.providerLabel('github'), 'github');
    });

    test('falls back to a generic message for unknown codes', () {
      expect(
        OAuthFlow.errorMessage('emailAlreadyRegistered'),
        contains('already exists'),
      );
      expect(OAuthFlow.errorMessage(null), 'Sign-in failed. Please try again.');
    });
  });
}

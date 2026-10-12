import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';

import '../services/api_client.dart';
import '../services/oauth_flow.dart';
import '../utils/logger.dart';

/// Runs the OAuth flow for [provider] in a WebView and pops with an
/// [OAuthResult], or null when the user closes it.
class OAuthScreen extends StatefulWidget {
  final String provider;
  final String apiBaseUrl;
  final String frontendUrl;

  const OAuthScreen({
    super.key,
    required this.provider,
    required this.apiBaseUrl,
    required this.frontendUrl,
  });

  @override
  State<OAuthScreen> createState() => _OAuthScreenState();
}

class _OAuthScreenState extends State<OAuthScreen> {
  static const _tag = 'OAuthScreen';
  static const _bgColor = Color(0xFF0A0A0A);

  final _cookieManager = CookieManager.instance();

  late final Uri _frontendUri = Uri.parse(widget.frontendUrl);
  late final Uri _apiUri = Uri.parse(widget.apiBaseUrl);

  /// Cookies from an earlier attempt would make the API reject the flow, so
  /// the WebView only loads once they are cleared.
  bool _ready = false;
  bool _finishing = false;
  int _progress = 0;

  @override
  void initState() {
    super.initState();
    _clearWebViewCookies().whenComplete(() {
      if (mounted) setState(() => _ready = true);
    });
  }

  /// The session now lives in the app's own cookie jar, and the WebView
  /// should not keep a second copy or the provider's login.
  Future<void> _clearWebViewCookies() async {
    try {
      await _cookieManager.deleteAllCookies();
    } catch (e) {
      Logger.error('Failed to clear WebView cookies', tag: _tag, error: e);
    }
  }

  /// Returns true when the navigation should be stopped.
  bool _handleUrl(Uri? url) {
    if (url == null || _finishing) return _finishing;

    final step = OAuthFlow.classify(url, _frontendUri);
    switch (step.kind) {
      case OAuthStepKind.proceed:
        return false;
      case OAuthStepKind.signedIn:
        _finish(_readSession());
      case OAuthStepKind.pendingActivation:
        _finish(Future.value(const OAuthPendingActivation()));
      case OAuthStepKind.failed:
        Logger.error('OAuth flow failed: ${step.errorCode}', tag: _tag);
        _finish(
          Future.value(
            OAuthFailed(
              OAuthFlow.errorMessage(step.errorCode),
              code: step.errorCode,
            ),
          ),
        );
    }
    return true;
  }

  Future<OAuthResult> _readSession() async {
    // WKWebView can store a redirect's cookies a moment after the redirect.
    for (var attempt = 0; attempt < 10; attempt++) {
      for (final uri in [_apiUri, _frontendUri]) {
        final cookie = await _cookieManager.getCookie(
          url: WebUri.uri(uri),
          name: ApiClient.sessionCookieName,
        );
        final value = cookie?.value?.toString();
        if (value != null && value.isNotEmpty) {
          Logger.log('OAuth session received', tag: _tag);
          return OAuthSignedIn(value);
        }
      }
      await Future<void>.delayed(const Duration(milliseconds: 200));
    }

    Logger.error('OAuth finished without a session cookie', tag: _tag);
    return const OAuthFailed('Sign-in finished, but no session was received.');
  }

  Future<void> _finish(Future<OAuthResult> result) async {
    if (_finishing) return;
    setState(() => _finishing = true);

    OAuthResult value;
    try {
      value = await result;
    } catch (e, stackTrace) {
      Logger.error(
        'Failed to finish OAuth flow',
        tag: _tag,
        error: e,
        stackTrace: stackTrace,
      );
      value = const OAuthFailed('Sign-in failed. Please try again.');
    }

    await _clearWebViewCookies();
    if (!mounted) return;
    Navigator.of(context).pop(value);
  }

  void _fail(String message) {
    _finish(Future.value(OAuthFailed(message)));
  }

  Future<void> _cancel() async {
    if (_finishing) return;
    _finishing = true;
    await _clearWebViewCookies();
    if (!mounted) return;
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final label = OAuthFlow.providerLabel(widget.provider);

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _cancel();
      },
      child: Scaffold(
        backgroundColor: _bgColor,
        appBar: AppBar(
          backgroundColor: _bgColor,
          leading: IconButton(
            icon: const Icon(Icons.close, color: Colors.white70),
            tooltip: 'Cancel',
            onPressed: _cancel,
          ),
          title: Text(
            'Sign in with $label',
            style: const TextStyle(color: Colors.white, fontSize: 16),
          ),
          bottom: PreferredSize(
            preferredSize: const Size.fromHeight(2),
            child: (_ready && _progress < 100) || _finishing
                ? LinearProgressIndicator(
                    minHeight: 2,
                    value: _finishing ? null : _progress / 100,
                  )
                : const SizedBox(height: 2),
          ),
        ),
        body: Stack(
          children: [
            if (_ready) _buildWebView(),
            if (!_ready || _finishing)
              const ColoredBox(
                color: _bgColor,
                child: Center(child: CircularProgressIndicator()),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildWebView() {
    return InAppWebView(
      initialUrlRequest: URLRequest(
        url: WebUri.uri(
          OAuthFlow.authorizeUri(widget.apiBaseUrl, widget.provider),
        ),
        // The API only starts the flow from a form POST, like the website.
        method: 'POST',
        body: Uint8List(0),
        headers: const {'Content-Type': 'application/x-www-form-urlencoded'},
      ),
      initialSettings: InAppWebViewSettings(
        useShouldOverrideUrlLoading: true,
        transparentBackground: true,
      ),
      shouldOverrideUrlLoading: (controller, action) async {
        final url = action.request.url;
        // Provider pages can link to their native apps, which would leave
        // the flow.
        if (url != null && url.scheme != 'http' && url.scheme != 'https') {
          return NavigationActionPolicy.CANCEL;
        }
        return _handleUrl(url)
            ? NavigationActionPolicy.CANCEL
            : NavigationActionPolicy.ALLOW;
      },
      // Covers redirects a platform did not offer to shouldOverrideUrlLoading
      // and the frontend's client-side navigation after signup.
      onLoadStart: (controller, url) => _handleUrl(url),
      onUpdateVisitedHistory: (controller, url, _) => _handleUrl(url),
      onProgressChanged: (controller, progress) {
        if (mounted) setState(() => _progress = progress);
      },
      onReceivedError: (controller, request, error) {
        if (request.isForMainFrame != true ||
            error.type == WebResourceErrorType.CANCELLED) {
          return;
        }
        Logger.error('OAuth page failed: ${error.description}', tag: _tag);
        _fail('Could not load the sign-in page: ${error.description}');
      },
      // The API answers a rejected flow with a problem response instead of
      // a redirect, which would otherwise show up as raw JSON.
      onReceivedHttpError: (controller, request, response) {
        final status = response.statusCode ?? 0;
        if (request.isForMainFrame != true ||
            status < 400 ||
            request.url.host.toLowerCase() != _apiUri.host.toLowerCase()) {
          return;
        }
        Logger.error('OAuth API returned $status', tag: _tag);
        _fail(
          status == 429
              ? 'Too many sign-in attempts. Please wait a moment.'
              : 'The server rejected the sign-in attempt ($status).',
        );
      },
    );
  }
}

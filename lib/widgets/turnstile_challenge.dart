import 'package:flutter/material.dart';
import 'package:webview_flutter/webview_flutter.dart';

/// Renders a Cloudflare Turnstile widget inside a WebView and reports the token
/// it produces.
///
/// `POST /2/account/login` requires a verified Turnstile token, and the only
/// way to obtain one is to run Cloudflare's browser-side widget. The official
/// web frontend does exactly this; see `Turnstile.svelte` in OpenShock/Frontend.
///
/// The page is loaded with [baseUrl] as its origin rather than as a bare
/// `data:` document, because Turnstile validates the hostname of the page
/// hosting the widget against the domains registered for the site key. Passing
/// the instance's own frontend URL is what makes the challenge accepted.
class TurnstileChallenge extends StatefulWidget {
  /// Site key from `GET /1` (`turnstileSiteKey`).
  final String siteKey;

  /// Origin the widget is rendered under. Use the instance's `frontendUrl`.
  final String baseUrl;

  /// Turnstile action label. The web frontend uses `signin` on its login page.
  final String action;

  /// Called with the token, or null when the challenge expires or errors.
  final ValueChanged<String?> onToken;

  const TurnstileChallenge({
    super.key,
    required this.siteKey,
    required this.baseUrl,
    required this.onToken,
    this.action = 'signin',
  });

  @override
  State<TurnstileChallenge> createState() => _TurnstileChallengeState();
}

class _TurnstileChallengeState extends State<TurnstileChallenge> {
  static const _channelName = 'TurnstileBridge';

  late final WebViewController _controller;

  @override
  void initState() {
    super.initState();

    _controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setBackgroundColor(Colors.transparent)
      ..addJavaScriptChannel(_channelName, onMessageReceived: _onMessage)
      ..loadHtmlString(_buildHtml(), baseUrl: widget.baseUrl);
  }

  void _onMessage(JavaScriptMessage message) {
    final value = message.message;
    // The bridge reports an empty string for expiry, timeout and error, all of
    // which invalidate any token already handed over.
    widget.onToken(value.isEmpty ? null : value);
  }

  String _buildHtml() {
    return '''
<!doctype html>
<html>
  <head>
    <meta charset="utf-8" />
    <meta name="viewport" content="width=device-width, initial-scale=1" />
    <script src="https://challenges.cloudflare.com/turnstile/v0/api.js?render=explicit"></script>
    <style>
      html, body {
        margin: 0;
        padding: 0;
        background: transparent;
        display: flex;
        align-items: center;
        justify-content: center;
        min-height: 70px;
      }
    </style>
  </head>
  <body>
    <div id="widget"></div>
    <script>
      function report(token) {
        $_channelName.postMessage(token || '');
      }
      function render() {
        window.turnstile.render('#widget', {
          sitekey: '${widget.siteKey}',
          action: '${widget.action}',
          theme: 'dark',
          callback: report,
          'expired-callback': function () { report(''); },
          'timeout-callback': function () { report(''); },
          'error-callback': function () { report(''); }
        });
      }
      if (window.turnstile) {
        window.turnstile.ready(render);
      } else {
        window.onloadTurnstileCallback = render;
        window.addEventListener('load', function () {
          if (window.turnstile) window.turnstile.ready(render);
        });
      }
    </script>
  </body>
</html>
''';
  }

  @override
  Widget build(BuildContext context) {
    // Turnstile's widget is a fixed 300x65; give it a little room to breathe.
    return SizedBox(
      height: 80,
      child: WebViewWidget(controller: _controller),
    );
  }
}

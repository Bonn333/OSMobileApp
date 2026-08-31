import 'package:flutter/material.dart';
import 'package:webview_flutter/webview_flutter.dart';

/// Renders a Cloudflare Turnstile widget in a WebView and reports its token.
class TurnstileChallenge extends StatefulWidget {
  final String siteKey;

  /// Turnstile checks this origin against the domains allowed for the site key.
  final String baseUrl;

  final String action;

  /// Null when the challenge expires or errors.
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
    return SizedBox(height: 80, child: WebViewWidget(controller: _controller));
  }
}

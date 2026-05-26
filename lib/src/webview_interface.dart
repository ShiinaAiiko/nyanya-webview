import 'package:flutter/widgets.dart';

abstract class WebViewInterface {
  Widget build(BuildContext context);

  Future<void> loadUrl(String url);

  Future<void> reload();

  Future<void> goBack();

  Future<void> goForward();

  Future<bool> canGoBack();

  Future<bool> canGoForward();

  Future<void> evaluateJavascript(String script);

  Future<void> postMessage(String message);

  Future<void> setWebMessageHandler(WebViewMessageHandler handler);

  Future<void> openInBrowser(String url);

  Future<void> dispose();
}

typedef WebViewMessageHandler = void Function(String message);
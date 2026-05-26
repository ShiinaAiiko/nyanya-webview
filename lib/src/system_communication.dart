import 'dart:async';
import 'package:webview_flutter/webview_flutter.dart';
import 'webview_communication_interface.dart';

/// SystemWebView 通信实现（使用 webview_flutter 的 JavaScriptChannel）
class SystemCommunication implements IWebViewCommunication {
  @override
  final String sessionId;
  final WebViewController _controller;
  void Function(String message)? _messageHandler;

  SystemCommunication({
    required this.sessionId,
    required WebViewController controller,
  }) : _controller = controller;

  /// 这个方法由 SystemWebview 在创建 JavaScriptChannel 时调用
  void handleMessageFromWeb(String message) {
    _messageHandler?.call(message);
  }

  @override
  Future<void> postMessage(String message) async {
    try {
      final script = '''
        if (window.onFlutterMessage) {
          window.onFlutterMessage($message);
        }
        if (window.postMessage) {
          window.postMessage($message, '*');
        }
      ''';
      await _controller.runJavaScript(script);
    } catch (e) {
      print('[SystemCommunication] Error posting message: $e');
    }
  }

  @override
  void setMessageHandler(void Function(String message) handler) {
    _messageHandler = handler;
  }

  @override
  Future<bool> checkReady() async {
    try {
      final url = await _controller.currentUrl();
      return url != null;
    } catch (e) {
      return false;
    }
  }

  @override
  Future<bool> checkHealth() async {
    // SystemWebView 不使用 session 概念，总是返回 true
    return true;
  }

  @override
  Future<void> loadUrl(String url) async {
    await _controller.loadRequest(Uri.parse(url));
  }

  @override
  Future<void> reload() async {
    await _controller.reload();
  }

  @override
  Future<void> goBack() async {
    if (await _controller.canGoBack()) {
      await _controller.goBack();
    }
  }

  @override
  Future<void> goForward() async {
    if (await _controller.canGoForward()) {
      await _controller.goForward();
    }
  }

  @override
  Future<bool> canGoBack() async {
    return await _controller.canGoBack();
  }

  @override
  Future<bool> canGoForward() async {
    return await _controller.canGoForward();
  }

  @override
  Future<void> evaluateJavascript(String script) async {
    try {
      await _controller.runJavaScript(script);
    } catch (e) {
      print('[SystemCommunication] Error evaluating JS: $e');
    }
  }

  @override
  Future<void> shutdown() async {
    // SystemWebView 关闭通道，清空引用，释放内存
    _messageHandler = null;
  }

  @override
  void dispose() {
    _messageHandler = null;
  }
}

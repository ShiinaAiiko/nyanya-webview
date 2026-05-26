import 'dart:async';
import 'package:flutter/services.dart';
import 'webview_communication_interface.dart';

/// GeckoView 通信实现（使用 MethodChannel）
class GeckoCommunication implements IWebViewCommunication {
  @override
  final String sessionId;
  final MethodChannel _channel;
  void Function(String message)? _messageHandler;

  GeckoCommunication({
    required this.sessionId,
    required MethodChannel channel,
  }) : _channel = channel {
    _channel.setMethodCallHandler(_handleMethodCall);
  }

  /// 处理从 Web 端收到的消息
  void handleMessageFromWeb(String message) {
    _messageHandler?.call(message);
  }

  Future<dynamic> _handleMethodCall(MethodCall call) async {
    switch (call.method) {
      case 'onWebMessage':
        final String message = call.arguments as String;
        handleMessageFromWeb(message);
        return {'status': 'ok'};
      default:
        return {'status': 'error', 'error': 'Unknown method'};
    }
  }

  @override
  Future<void> postMessage(String message) async {
    print('NyaNyaWebViewLog sendMessage $message');
    await _channel.invokeMethod('postMessage', {'message': message});
  }

  @override
  void setMessageHandler(void Function(String message) handler) {
    _messageHandler = handler;
  }

  @override
  Future<bool> checkReady() async {
    try {
      return await _channel.invokeMethod<bool>('checkWebViewReady') ?? false;
    } catch (e) {
      return false;
    }
  }

  @override
  Future<bool> checkHealth() async {
    try {
      return await _channel.invokeMethod<bool>('checkSessionsHealth') ?? false;
    } catch (e) {
      return false;
    }
  }

  @override
  Future<void> loadUrl(String url) async {
    await _channel.invokeMethod('loadUrl', {'url': url});
  }

  @override
  Future<void> reload() async {
    await _channel.invokeMethod('reload');
  }

  @override
  Future<void> goBack() async {
    await _channel.invokeMethod('goBack');
  }

  @override
  Future<void> goForward() async {
    await _channel.invokeMethod('goForward');
  }

  @override
  Future<bool> canGoBack() async {
    return await _channel.invokeMethod<bool>('canGoBack') ?? false;
  }

  @override
  Future<bool> canGoForward() async {
    return await _channel.invokeMethod<bool>('canGoForward') ?? false;
  }

  @override
  Future<void> evaluateJavascript(String script) async {
    await _channel.invokeMethod('evaluateJavascript', {'script': script});
  }

  @override
  Future<void> shutdown() async {
    // GeckoView 关闭 GeckoRuntime，清空引用，释放内存
    try {
      await _channel.invokeMethod('shutdownGeckoRuntime');
    } catch (e) {
      print('[GeckoCommunication] Error shutting down GeckoRuntime: $e');
    }
    _channel.setMethodCallHandler(null);
    _messageHandler = null;
  }

  @override
  void dispose() {
    _channel.setMethodCallHandler(null);
    _messageHandler = null;
  }
}

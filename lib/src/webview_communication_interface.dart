import 'dart:async';

/// 统一的 WebView 通信接口
/// 支持 GeckoView (MethodChannel) 和 SystemWebView (JavaScriptChannel)
abstract class IWebViewCommunication {
  /// 会话 ID，用于区分不同标签页
  String get sessionId;

  /// 向 WebView 发送消息
  Future<void> postMessage(String message);

  /// 设置从 WebView 接收消息的处理器
  void setMessageHandler(void Function(String message) handler);

  /// 检查 WebView 是否准备就绪
  Future<bool> checkReady();

  /// 检查会话健康状态
  Future<bool> checkHealth();

  /// 加载 URL
  Future<void> loadUrl(String url);

  /// 重新加载
  Future<void> reload();

  /// 后退
  Future<void> goBack();

  /// 前进
  Future<void> goForward();

  /// 是否可以后退
  Future<bool> canGoBack();

  /// 是否可以前进
  Future<bool> canGoForward();

  /// 执行 JavaScript
  Future<void> evaluateJavascript(String script);

  /// 关闭 GeckoRuntime（仅 GeckoView 有效）
  Future<void> shutdown();

  /// 清理资源
  void dispose();
}

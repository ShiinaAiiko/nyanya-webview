import 'dart:async';
import 'package:flutter/material.dart';
import 'package:webview_flutter/webview_flutter.dart';
import 'webview_options.dart';
import 'system_communication.dart';
import 'webview_communication_interface.dart';

typedef NyaNyaMessageHandler = void Function(String message);
typedef NyaNyaChannelCreatedCallback = void Function(dynamic channel);
typedef NyaNyaCommunicationCreatedCallback = void Function(
    IWebViewCommunication comm);

class SystemWebview extends StatefulWidget {
  final WebViewOptions options;
  final NyaNyaMessageHandler messageHandler;
  final NyaNyaChannelCreatedCallback? onChannelCreated;
  final NyaNyaCommunicationCreatedCallback? onCommunicationCreated;
  final OpenUrlHandler? onOpenUrl;
  final String sessionId;

  const SystemWebview({
    super.key,
    required this.options,
    required this.messageHandler,
    this.onChannelCreated,
    this.onCommunicationCreated,
    this.onOpenUrl,
    required this.sessionId,
  });

  @override
  State<SystemWebview> createState() => _SystemWebviewState();
}

class _SystemWebviewState extends State<SystemWebview> {
  late final WebViewController _controller;
  SystemCommunication? _communication;
  bool _isDisposed = false;
  late WebViewOptions _currentOptions;
  bool _canGoBack = false;
  bool _canGoForward = false;
  String? _currentTitle;
  String? _currentUrl;

  @override
  void initState() {
    super.initState();
    _currentOptions = widget.options;
    print(
        '[NyaNyaWebViewLog] SystemWebview.initState: this.hashCode=${identityHashCode(this)}, widget.onOpenUrl = ${widget.onOpenUrl}');

    _initializeWebViewController();
  }

  @override
  void didUpdateWidget(SystemWebview oldWidget) {
    super.didUpdateWidget(oldWidget);
    print(
        '[NyaNyaWebViewLog] SystemWebview.didUpdateWidget: this.hashCode=${identityHashCode(this)}');
    if (widget.options != oldWidget.options) {
      setState(() {
        _currentOptions = widget.options;
      });
    }
  }

  void _initializeWebViewController() {
    _controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setNavigationDelegate(
        NavigationDelegate(
          onPageStarted: (String url) {
            print('[NyaNyaWebViewLog] SystemWebview: onPageStarted, url=$url');
            _currentUrl = url;
            _sendPageStartEvent(url);
          },
          onPageFinished: (String url) async {
            print('[NyaNyaWebViewLog] SystemWebview: onPageFinished, url=$url');
            _currentUrl = url;
            await _injectFlutterBridge();
            _sendPageStopEvent(true);
            final title = await _controller.getTitle();
            if (title != null && title.isNotEmpty) {
              _currentTitle = title;
              _sendTitleChangeEvent(title);
            }
            _updateNavigationState();
          },
          onUrlChange: (UrlChange change) {
            final url = change.url;
            if (url != null) {
              print('[NyaNyaWebViewLog] SystemWebview: onUrlChange, url=$url');
              _currentUrl = url;
              _sendLocationChangeEvent(url);
            }
          },
          onNavigationRequest: (NavigationRequest request) {
            final url = request.url;
            print(
                '[NyaNyaWebViewLog] SystemWebview: onNavigationRequest, url=$url');

            if (_currentOptions.newTabBehavior == NewTabBehavior.delegate &&
                widget.onOpenUrl != null &&
                !url.startsWith('javascript:') &&
                !url.startsWith('http://127.0.0.1:')) {
              // 判断是否是新窗口请求（通过目标或用户交互判断）
              // 对于 webview_flutter，新窗口通常通过 request.isMainFrame 判断
              // 或者通过用户的点击行为判断
              // 这里我们假设所有外部链接都当作新窗口处理
              print(
                  '[NyaNyaWebViewLog] SystemWebview: Delegating navigation to onOpenUrl');
              widget.onOpenUrl!(url, '_blank');
              return NavigationDecision.prevent;
            }
            return NavigationDecision.navigate;
          },
          onWebResourceError: (WebResourceError error) {
            print(
                '[NyaNyaWebViewLog] SystemWebview: onWebResourceError, error=${error.description}');
          },
        ),
      )
      ..addJavaScriptChannel(
        'NyanyaBridge',
        onMessageReceived: (JavaScriptMessage message) {
          print(
              '[NyaNyaWebViewLog] SystemWebview: Received message from JS: ${message.message}');
          // 同时转发给通信接口和原始处理器
          _communication?.handleMessageFromWeb(message.message);
          widget.messageHandler(message.message);
        },
      );

    // 创建通信接口
    _communication = SystemCommunication(
      sessionId: widget.sessionId,
      controller: _controller,
    );
    _communication?.setMessageHandler(widget.messageHandler);

    // 加载初始 URL
    _controller.loadRequest(Uri.parse(widget.options.initialUrl));

    // 通知 Flutter 层 channel 已创建（保持向后兼容）
    widget.onChannelCreated?.call(_controller);
    // 通知通信接口已创建
    widget.onCommunicationCreated?.call(_communication!);
  }

  Future<void> _injectFlutterBridge() async {
    final bridgeScript = '''
      (function() {
        window.isFlutterApp = true;
        window.flutterServerPort = ${widget.options.serverPort};
        window.flutterServerHost = 'http://127.0.0.1:${widget.options.serverPort}';
        window.nyanyaSessionId = '${widget.sessionId}';
        
        if (!window.nyanyaWebView) {
          window.nyanyaWebView = {
            postMessage: function(message) {
              if (typeof NyanyaBridge !== 'undefined') {
                NyanyaBridge.postMessage(message);
              }
            }
          };
        }
        
        window.addEventListener('message', function(event) {
          if (event.data && typeof event.data === 'object') {
            if (event.data.type === 'GEOLOCATION_REQUEST') {
              if (window.nyanyaWebView) {
                window.nyanyaWebView.postMessage(JSON.stringify({
                  type: 'geolocation',
                  payload: event.data
                }));
              }
            }
          }
        });
      })();
    ''';

    try {
      await _controller.runJavaScript(bridgeScript);
      print('[NyaNyaWebViewLog] SystemWebview: Flutter bridge injected');
    } catch (e) {
      print('[NyaNyaWebViewLog] SystemWebview: Error injecting bridge: $e');
    }
  }

  void _sendPageStartEvent(String url) {
    widget.messageHandler('{"type":"onPageStart","payload":{"url":"$url"}}');
  }

  void _sendPageStopEvent(bool success) {
    widget
        .messageHandler('{"type":"onPageStop","payload":{"success":$success}}');
  }

  void _sendTitleChangeEvent(String title) {
    widget.messageHandler(
        '{"type":"onTitleChange","payload":{"title":"$title"}}');
  }

  void _sendLocationChangeEvent(String url) {
    widget
        .messageHandler('{"type":"onLocationChange","payload":{"url":"$url"}}');
  }

  Future<void> _updateNavigationState() async {
    final canGoBack = await _controller.canGoBack();
    final canGoForward = await _controller.canGoForward();

    if (mounted && (canGoBack != _canGoBack || canGoForward != _canGoForward)) {
      setState(() {
        _canGoBack = canGoBack;
        _canGoForward = canGoForward;
      });

      // 通知 tab 状态变化
      final url = _currentUrl ?? '';
      final title = _currentTitle ?? '';
      widget.messageHandler(
          '{"type":"onTabChanged","payload":{"url":"$url","title":"$title"}}');
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isDisposed) {
      return const SizedBox.shrink();
    }
    return WebViewWidget(controller: _controller);
  }

  Future<void> loadUrl(String url) async {
    print('[NyaNyaWebViewLog] SystemWebview: Loading URL: $url');
    await _controller.loadRequest(Uri.parse(url));
  }

  Future<void> reload() async {
    print('[NyaNyaWebViewLog] SystemWebview: Reloading');
    await _controller.reload();
  }

  Future<void> goBack() async {
    print('[NyaNyaWebViewLog] SystemWebview: Going back');
    if (await _controller.canGoBack()) {
      await _controller.goBack();
    } else {
      widget.messageHandler('{"type":"onRequestExitApp"}');
    }
  }

  Future<void> goForward() async {
    print('[NyaNyaWebViewLog] SystemWebview: Going forward');
    if (await _controller.canGoForward()) {
      await _controller.goForward();
    }
  }

  Future<bool> canGoBack() async {
    return await _controller.canGoBack();
  }

  Future<bool> canGoForward() async {
    return await _controller.canGoForward();
  }

  Future<void> evaluateJavascript(String script) async {
    try {
      await _controller.runJavaScript(script);
    } catch (e) {
      print('[NyaNyaWebViewLog] SystemWebview: Error evaluating JS: $e');
    }
  }

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
      print('[NyaNyaWebViewLog] SystemWebview: Error posting message: $e');
    }
  }

  Future<void> setGeolocation(double latitude, double longitude,
      {double accuracy = 10.0,
      double? altitude,
      double? heading,
      double? speed,
      double? timestamp}) async {
    final positionJson = buildString({
      'coords': {
        'latitude': latitude,
        'longitude': longitude,
        'accuracy': accuracy,
        if (altitude != null) 'altitude': altitude,
        if (heading != null) 'heading': heading,
        if (speed != null) 'speed': speed,
        'altitudeAccuracy': accuracy,
      },
      'timestamp': timestamp ?? DateTime.now().millisecondsSinceEpoch,
    });

    final script = '''
      (function() {
        if (window._geolocationSuccessCallback) {
          window._geolocationSuccessCallback($positionJson);
        }
      })();
    ''';
    await evaluateJavascript(script);
  }

  Future<void> setGeolocationError(String code, String message) async {
    final script = '''
      (function() {
        if (window._geolocationErrorCallback) {
          window._geolocationErrorCallback({code: '$code', message: '$message'});
        }
      })();
    ''';
    await evaluateJavascript(script);
  }

  Future<void> openInBrowser(String url) async {
    try {
      if (url.isNotEmpty) {
        final script = '''
          window.location.href = '$url';
        ''';
        await evaluateJavascript(script);
      }
    } catch (e) {
      print('[NyaNyaWebViewLog] SystemWebview: Error opening in browser: $e');
    }
  }

  Future<bool> checkWebViewReady() async {
    try {
      final url = await _controller.currentUrl();
      return url != null;
    } catch (e) {
      return false;
    }
  }

  Future<bool> checkSessionsHealth() async {
    return true;
  }

  @override
  void dispose() {
    print(
        '[NyaNyaWebViewLog] SystemWebview.dispose CALLED! this.hashCode=${identityHashCode(this)}');
    _isDisposed = true;

    _communication?.shutdown();
    _communication?.dispose();
    _communication = null;

    try {
      _controller.clearCache();
    } catch (e) {
      print('[NyaNyaWebViewLog] Error cleaning up WebViewController: $e');
    }

    super.dispose();
  }
}

String buildString(Map<String, dynamic> map) {
  StringBuffer buffer = StringBuffer();
  buffer.write('{');
  bool first = true;
  map.forEach((key, value) {
    if (!first) {
      buffer.write(',');
    }
    first = false;
    buffer.write('"$key":');
    if (value is Map) {
      buffer.write(buildString(value as Map<String, dynamic>));
    } else if (value is String) {
      buffer.write('"$value"');
    } else {
      buffer.write(value);
    }
  });
  buffer.write('}');
  return buffer.toString();
}

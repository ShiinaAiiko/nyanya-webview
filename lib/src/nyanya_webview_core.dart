import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:webview_flutter/webview_flutter.dart';
import 'webview_options.dart';
import 'gecko_webview.dart' as gecko;
import 'system_webview.dart' as system;
import 'webview_communication_interface.dart';

typedef NyaNyaMessageHandler = void Function(String message);
typedef NyaNyaChannelCreatedCallback = void Function(dynamic channel);
typedef NyaNyaCommunicationCreatedCallback = void Function(
    IWebViewCommunication comm);
typedef NyaNyaCloseCallback = void Function();

class NyaNyaWebview extends StatefulWidget {
  final WebViewOptions options;
  final NyaNyaMessageHandler messageHandler;
  final GlobalKey<_NyaNyaWebviewState>? controllerKey;
  final NyaNyaChannelCreatedCallback? onChannelCreated;
  final NyaNyaCommunicationCreatedCallback? onCommunicationCreated;
  final OpenUrlHandler? onOpenUrl;
  final NyaNyaCloseCallback? onClose;
  final String sessionId;

  const NyaNyaWebview({
    super.key,
    required this.options,
    required this.messageHandler,
    this.controllerKey,
    this.onChannelCreated,
    this.onCommunicationCreated,
    this.onOpenUrl,
    this.onClose,
    required this.sessionId,
  });

  @override
  State<NyaNyaWebview> createState() => _NyaNyaWebviewState();
}

class _NyaNyaWebviewState extends State<NyaNyaWebview>
    with AutomaticKeepAliveClientMixin {
  MethodChannel? _channel;
  WebViewController? _webViewController;
  IWebViewCommunication? _communication;
  int? _platformViewId;
  bool _isDisposed = false;

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    print(
        '[NyaNyaWebViewLog-Flutter] NyaNyaWebview.initState called! this.hashCode=${identityHashCode(this)}');
  }

  @override
  void didUpdateWidget(NyaNyaWebview oldWidget) {
    super.didUpdateWidget(oldWidget);
    print(
        '[NyaNyaWebViewLog-Flutter] NyaNyaWebview.didUpdateWidget called! this.hashCode=${identityHashCode(this)}');
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    if (_isDisposed) {
      return const SizedBox.shrink();
    }

    print(
        '[NyaNyaWebViewLog-Flutter] NyaNyaWebview.build: this.hashCode=${identityHashCode(this)}, engine=${widget.options.engine}, onOpenUrl callback exists: ${widget.onOpenUrl != null}');

    if (defaultTargetPlatform == TargetPlatform.android) {
      switch (widget.options.engine) {
        case WebViewEngine.gecko:
          return gecko.GeckoWebview(
            options: widget.options,
            messageHandler: widget.messageHandler,
            onChannelCreated: (channel) {
              _channel = channel;
              _webViewController = null;
              widget.onChannelCreated?.call(channel);
            },
            onCommunicationCreated: (comm) {
              _communication = comm;
              widget.onCommunicationCreated?.call(comm);
            },
            onOpenUrl: widget.onOpenUrl,
            onClose: widget.onClose,
            sessionId: widget.sessionId,
          );
        case WebViewEngine.system:
          return system.SystemWebview(
            options: widget.options,
            messageHandler: widget.messageHandler,
            onChannelCreated: (controller) {
              _webViewController = controller as WebViewController?;
              _channel = null;
              widget.onChannelCreated?.call(controller);
            },
            onCommunicationCreated: (comm) {
              _communication = comm;
              widget.onCommunicationCreated?.call(comm);
            },
            onOpenUrl: widget.onOpenUrl,
            sessionId: widget.sessionId,
          );
      }
    }

    // For iOS and other platforms, use system webview
    return system.SystemWebview(
      options: widget.options,
      messageHandler: widget.messageHandler,
      onChannelCreated: (controller) {
        _webViewController = controller as WebViewController?;
        _channel = null;
      },
      onCommunicationCreated: (comm) {
        _communication = comm;
        widget.onCommunicationCreated?.call(comm);
      },
      onOpenUrl: widget.onOpenUrl,
      sessionId: widget.sessionId,
    );
  }

  Future<void> loadUrl(String url) async {
    if (_communication != null) {
      await _communication!.loadUrl(url);
      return;
    }

    if (_webViewController != null) {
      await _webViewController!.loadRequest(Uri.parse(url));
      return;
    }

    if (_channel == null) {
      await _waitForChannel();
    }
    await _channel?.invokeMethod('loadUrl', {'url': url});
  }

  Future<void> reload() async {
    print(
        '[NyaNyaWebViewLog-Flutter] NyaNyaWebview.reload _handleRefresh CALLED! this.hashCode=${identityHashCode(this)}, _channel=$_channel, _webViewController=$_webViewController');

    if (_communication != null) {
      await _communication!.reload();
      return;
    }

    if (_webViewController != null) {
      await _webViewController!.reload();
      return;
    }

    if (_channel == null) {
      await _waitForChannel();
    }
    print(
        '[NyaNyaWebViewLog-Flutter] NyaNyaWebview.reload: _channel=$_channel');
    await _channel?.invokeMethod('reload');
  }

  Future<void> goBack() async {
    print('[NyaNyaWebViewLog-Flutter] NyaNyaWebview.goBack called');

    if (_communication != null) {
      await _communication!.goBack();
      return;
    }

    if (_webViewController != null) {
      if (await _webViewController!.canGoBack()) {
        await _webViewController!.goBack();
      }
      return;
    }

    if (_channel == null) {
      await _waitForChannel();
    }
    print(
        '[NyaNyaWebViewLog-Flutter] NyaNyaWebview.goBack: _channel=$_channel');
    await _channel?.invokeMethod('goBack');
  }

  Future<void> goForward() async {
    print('[NyaNyaWebViewLog-Flutter] NyaNyaWebview.goForward called');

    if (_communication != null) {
      await _communication!.goForward();
      return;
    }

    if (_webViewController != null) {
      if (await _webViewController!.canGoForward()) {
        await _webViewController!.goForward();
      }
      return;
    }

    if (_channel == null) {
      await _waitForChannel();
    }
    print(
        '[NyaNyaWebViewLog-Flutter] NyaNyaWebview.goForward: _channel=$_channel');
    await _channel?.invokeMethod('goForward');
  }

  Future<bool> canGoBack() async {
    print(
        '[NyaNyaWebViewLog-Flutter] updateNavigationState NyaNyaWebview.canGoBack CALLED! this.hashCode=${identityHashCode(this)}, _channel=$_channel');

    if (_communication != null) {
      return await _communication!.canGoBack();
    }

    if (_webViewController != null) {
      return await _webViewController!.canGoBack();
    }

    return await _channel?.invokeMethod<bool>('canGoBack') ?? false;
  }

  Future<bool> canGoForward() async {
    print(
        '[NyaNyaWebViewLog-Flutter] updateNavigationState NyaNyaWebview.canGoForward CALLED! this.hashCode=${identityHashCode(this)}, _channel=$_channel');

    if (_communication != null) {
      return await _communication!.canGoForward();
    }

    if (_webViewController != null) {
      return await _webViewController!.canGoForward();
    }

    return await _channel?.invokeMethod<bool>('canGoForward') ?? false;
  }

  Future<void> evaluateJavascript(String script) async {
    if (_communication != null) {
      await _communication!.evaluateJavascript(script);
      return;
    }

    if (_webViewController != null) {
      await _webViewController!.runJavaScript(script);
      return;
    }
    await _channel?.invokeMethod('evaluateJavascript', {'script': script});
  }

  Future<void> postMessage(String message) async {
    if (_communication != null) {
      await _communication!.postMessage(message);
      return;
    }

    if (_webViewController != null) {
      final wrappedMessage = '''
        if (window.onFlutterMessage) {
          window.onFlutterMessage($message);
        }
        if (window.postMessage) {
          window.postMessage($message, '*');
        }
      ''';
      await _webViewController!.runJavaScript(wrappedMessage);
      return;
    }

    if (_channel == null) {
      await _waitForChannel();
    }
    await _channel?.invokeMethod('postMessage', {'message': message});
  }

  Future<void> openInBrowser(String url) async {
    if (_webViewController != null) {
      final script = '''
        window.location.href = '$url';
      ''';
      await _webViewController!.runJavaScript(script);
      return;
    }

    if (_channel == null) {
      await _waitForChannel();
    }
    await _channel?.invokeMethod('openInBrowser', {'url': url});
  }

  Future<void> _waitForChannel() async {
    int attempts = 0;
    const maxAttempts = 50;
    while (_channel == null &&
        _webViewController == null &&
        attempts < maxAttempts) {
      await Future.delayed(const Duration(milliseconds: 100));
      attempts++;
    }
  }

  Future<bool> checkWebViewReady() async {
    if (_communication != null) {
      return await _communication!.checkReady();
    }

    if (_webViewController != null) {
      try {
        final url = await _webViewController!.currentUrl();
        return url != null;
      } catch (e) {
        return false;
      }
    }

    if (_channel == null) return false;
    try {
      return await _channel?.invokeMethod<bool>('checkWebViewReady') ?? false;
    } catch (e) {
      return false;
    }
  }

  Future<bool> checkSessionsHealth() async {
    if (_communication != null) {
      return await _communication!.checkHealth();
    }

    if (_webViewController != null) {
      return true;
    }

    if (_channel == null) return false;
    try {
      return await _channel?.invokeMethod<bool>('checkSessionsHealth') ?? false;
    } catch (e) {
      return false;
    }
  }

  Future<void> shutdownGeckoRuntime() async {
    if (widget.options.engine == WebViewEngine.gecko) {
      await _channel?.invokeMethod('shutdownGeckoRuntime');
    }
  }

  @override
  void dispose() {
    print(
        '[NyaNyaWebViewLog-Flutter] NyaNyaWebview.dispose CALLED! this.hashCode=${identityHashCode(this)}, _channel=$_channel');
    _isDisposed = true;
    _communication?.dispose();
    _communication = null;
    _channel?.setMethodCallHandler(null);
    _channel?.invokeMethod('dispose');
    _channel = null;
    super.dispose();
  }
}

class NyaNyaWebviewController {
  final GlobalKey<_NyaNyaWebviewState> _key;
  MethodChannel? _channel;
  WebViewController? _webViewController;
  IWebViewCommunication? _communication;

  NyaNyaWebviewController() : _key = GlobalKey<_NyaNyaWebviewState>();

  GlobalKey<_NyaNyaWebviewState> get key => _key;

  void setChannel(dynamic channel) {
    if (channel is MethodChannel) {
      _channel = channel;
      _webViewController = null;
    } else if (channel is WebViewController) {
      _webViewController = channel;
      _channel = null;
    }
  }

  void setCommunication(IWebViewCommunication comm) {
    _communication = comm;
  }

  Future<void> loadUrl(String url) async {
    print(
        '[DEBUG] NyaNyaWebviewController.loadUrl() called, _key.currentState: ${_key.currentState}, _channel: $_channel, _webViewController: $_webViewController');
    if (_communication != null) {
      await _communication!.loadUrl(url);
      return;
    }
    if (_key.currentState != null) {
      await _key.currentState?.loadUrl(url);
    } else if (_webViewController != null) {
      await _webViewController!.loadRequest(Uri.parse(url));
    } else if (_channel != null) {
      await _channel?.invokeMethod('loadUrl', {'url': url});
    }
  }

  Future<bool> canGoBack() async {
    print(
        '[DEBUG] NyaNyaWebviewController.canGoBack() called, _key.currentState: ${_key.currentState}, _channel: $_channel, _webViewController: $_webViewController');
    if (_communication != null) {
      return await _communication!.canGoBack();
    }
    if (_webViewController != null) {
      return await _webViewController!.canGoBack();
    }
    if (_channel != null) {
      return await _channel!.invokeMethod<bool>('canGoBack') ?? false;
    }
    return _key.currentState?.canGoBack() ?? Future.value(false);
  }

  Future<bool> canGoForward() async {
    print(
        '[DEBUG] NyaNyaWebviewController.canGoForward() called, _key.currentState: ${_key.currentState}, _channel: $_channel, _webViewController: $_webViewController');
    if (_communication != null) {
      return await _communication!.canGoForward();
    }
    if (_webViewController != null) {
      return await _webViewController!.canGoForward();
    }
    if (_channel != null) {
      return await _channel!.invokeMethod<bool>('canGoForward') ?? false;
    }
    return _key.currentState?.canGoForward() ?? Future.value(false);
  }

  Future<void> reload() async {
    print(
        '[DEBUG] NyaNyaWebviewController.reload() called, _key.currentState: ${_key.currentState}, _channel: $_channel, _webViewController: $_webViewController');
    if (_communication != null) {
      await _communication!.reload();
      return;
    }
    if (_key.currentState != null) {
      await _key.currentState?.reload();
    } else if (_webViewController != null) {
      await _webViewController!.reload();
    } else if (_channel != null) {
      await _channel?.invokeMethod('reload');
    }
  }

  Future<void> goBack() async {
    print(
        '[DEBUG] NyaNyaWebviewController.goBack() called, _key.currentState: ${_key.currentState}, _channel: $_channel, _webViewController: $_webViewController');
    if (_communication != null) {
      await _communication!.goBack();
      return;
    }
    if (_key.currentState != null) {
      await _key.currentState?.goBack();
    } else if (_webViewController != null) {
      if (await _webViewController!.canGoBack()) {
        await _webViewController!.goBack();
      }
    } else if (_channel != null) {
      await _channel?.invokeMethod('goBack');
    }
  }

  Future<void> goForward() async {
    print(
        '[DEBUG] NyaNyaWebviewController.goForward() called, _key.currentState: ${_key.currentState}, _channel: $_channel, _webViewController: $_webViewController');
    if (_communication != null) {
      await _communication!.goForward();
      return;
    }
    if (_key.currentState != null) {
      await _key.currentState?.goForward();
    } else if (_webViewController != null) {
      if (await _webViewController!.canGoForward()) {
        await _webViewController!.goForward();
      }
    } else if (_channel != null) {
      await _channel?.invokeMethod('goForward');
    }
  }

  Future<void> evaluateJavascript(String script) async {
    print(
        '[DEBUG] NyaNyaWebviewController.evaluateJavascript() called, _key.currentState: ${_key.currentState}, _channel: $_channel, _webViewController: $_webViewController');
    if (_communication != null) {
      await _communication!.evaluateJavascript(script);
      return;
    }
    if (_key.currentState != null) {
      await _key.currentState?.evaluateJavascript(script);
    } else if (_webViewController != null) {
      await _webViewController!.runJavaScript(script);
    } else if (_channel != null) {
      await _channel?.invokeMethod('evaluateJavascript', {'script': script});
    }
  }

  Future<void> postMessage(String message) async {
    print(
        '[DEBUG] NyaNyaWebviewController.postMessage() called, _key.currentState: ${_key.currentState}, _channel: $_channel, _webViewController: $_webViewController');
    if (_communication != null) {
      await _communication!.postMessage(message);
      return;
    }
    if (_key.currentState != null) {
      await _key.currentState?.postMessage(message);
    } else if (_webViewController != null) {
      final wrappedMessage = '''
        if (window.onFlutterMessage) {
          window.onFlutterMessage($message);
        }
        if (window.postMessage) {
          window.postMessage($message, '*');
        }
      ''';
      await _webViewController!.runJavaScript(wrappedMessage);
    } else if (_channel != null) {
      await _channel?.invokeMethod('postMessage', {'message': message});
    }
  }

  Future<void> openInBrowser(String url) async {
    print(
        '[DEBUG] NyaNyaWebviewController.openInBrowser() called, _key.currentState: ${_key.currentState}, _channel: $_channel, _webViewController: $_webViewController');
    if (_key.currentState != null) {
      await _key.currentState?.openInBrowser(url);
    } else if (_webViewController != null) {
      final script = '''
        window.location.href = '$url';
      ''';
      await _webViewController!.runJavaScript(script);
    } else if (_channel != null) {
      await _channel?.invokeMethod('openInBrowser', {'url': url});
    }
  }

  Future<bool> checkWebViewReady() async {
    print(
        '[DEBUG] NyaNyaWebviewController.checkWebViewReady() called, _key.currentState: ${_key.currentState}, _channel: $_channel, _webViewController: $_webViewController');
    if (_communication != null) {
      return await _communication!.checkReady();
    }
    if (_key.currentState != null) {
      return await _key.currentState?.checkWebViewReady() ?? false;
    } else if (_webViewController != null) {
      try {
        final url = await _webViewController!.currentUrl();
        return url != null;
      } catch (e) {
        return false;
      }
    } else if (_channel != null) {
      return await _channel?.invokeMethod<bool>('checkWebViewReady') ?? false;
    }
    return false;
  }

  Future<bool> checkSessionsHealth() async {
    print(
        '[DEBUG] NyaNyaWebviewController.checkSessionsHealth() called, _key.currentState: ${_key.currentState}, _channel: $_channel, _webViewController: $_webViewController');
    if (_communication != null) {
      return await _communication!.checkHealth();
    }
    if (_webViewController != null) {
      return true;
    }
    if (_key.currentState != null) {
      return await _key.currentState?.checkSessionsHealth() ?? false;
    } else if (_channel != null) {
      return await _channel?.invokeMethod<bool>('checkSessionsHealth') ?? false;
    }
    return false;
  }

  Future<void> shutdownGeckoRuntime() async {
    print(
        '[DEBUG] NyaNyaWebviewController.shutdownGeckoRuntime() called, _key.currentState: ${_key.currentState}, _channel: $_channel, _webViewController: $_webViewController');
    if (_key.currentState != null) {
      await _key.currentState?.shutdownGeckoRuntime();
    } else if (_channel != null) {
      await _channel?.invokeMethod('shutdownGeckoRuntime');
    }
  }
}

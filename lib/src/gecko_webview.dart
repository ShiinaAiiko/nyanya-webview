import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'webview_options.dart';
import 'gecko_communication.dart';
import 'webview_communication_interface.dart';

typedef NyaNyaMessageHandler = void Function(String message);
typedef NyaNyaChannelCreatedCallback = void Function(MethodChannel channel);
typedef NyaNyaCommunicationCreatedCallback = void Function(
    IWebViewCommunication comm);
typedef NyaNyaCloseCallback = void Function();

class GeckoWebview extends StatefulWidget {
  final WebViewOptions options;
  final NyaNyaMessageHandler messageHandler;
  final NyaNyaChannelCreatedCallback? onChannelCreated;
  final NyaNyaCommunicationCreatedCallback? onCommunicationCreated;
  final OpenUrlHandler? onOpenUrl;
  final NyaNyaCloseCallback? onClose;
  final String sessionId;

  const GeckoWebview({
    super.key,
    required this.options,
    required this.messageHandler,
    this.onChannelCreated,
    this.onCommunicationCreated,
    this.onOpenUrl,
    this.onClose,
    required this.sessionId,
  });

  @override
  State<GeckoWebview> createState() => _GeckoWebviewState();
}

class _GeckoWebviewState extends State<GeckoWebview> {
  MethodChannel? _channel;
  GeckoCommunication? _communication;
  int? _platformViewId;
  bool _isDisposed = false;
  late WebViewOptions _currentOptions;

  @override
  void initState() {
    super.initState();
    _currentOptions = widget.options;
    print(
        '[NyaNyaWebViewLog-Flutter] GeckoWebview.initState: this.hashCode=${identityHashCode(this)}, widget.onOpenUrl = ${widget.onOpenUrl}');
  }

  @override
  void didUpdateWidget(GeckoWebview oldWidget) {
    super.didUpdateWidget(oldWidget);
    print(
        '[NyaNyaWebViewLog-Flutter] GeckoWebview.didUpdateWidget: this.hashCode=${identityHashCode(this)}');
    if (widget.options != oldWidget.options) {
      setState(() {
        _currentOptions = widget.options;
      });
    }
  }

  @override
  void dispose() {
    print(
        '[NyaNyaWebViewLog-Flutter] GeckoWebview.dispose CALLED! this.hashCode=${identityHashCode(this)}');
    _isDisposed = true;

    // 清理通信接口
    _communication?.shutdown();
    _communication?.dispose();
    _communication = null;

    // 清理 MethodChannel
    _channel?.setMethodCallHandler(null);
    _channel = null;

    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_isDisposed) {
      return const SizedBox.shrink();
    }

    if (defaultTargetPlatform == TargetPlatform.android) {
      return PlatformViewLink(
        viewType: 'geckoView',
        surfaceFactory:
            (BuildContext context, PlatformViewController controller) {
          return AndroidViewSurface(
            controller: controller as AndroidViewController,
            gestureRecognizers: const <Factory<OneSequenceGestureRecognizer>>{},
            hitTestBehavior: PlatformViewHitTestBehavior.opaque,
          );
        },
        onCreatePlatformView: (PlatformViewCreationParams params) {
          final controller = PlatformViewsService.initSurfaceAndroidView(
            id: params.id,
            viewType: 'geckoView',
            layoutDirection: TextDirection.ltr,
            creationParams: <String, dynamic>{
              'url': _currentOptions.initialUrl,
              'serverPort': _currentOptions.serverPort,
              'enableJavascript': _currentOptions.enableJavascript,
              'enableMixedContent': _currentOptions.enableMixedContent,
              'sessionId': widget.sessionId,
            },
            creationParamsCodec: const StandardMessageCodec(),
          );

          controller.addOnPlatformViewCreatedListener((int id) {
            print(
                '[NyaNyaWebViewLog-Flutter] GeckoWebview: Platform view created, id=$id, this.hashCode=${identityHashCode(this)}');
            _platformViewId = id;
            final channelName = 'club.aiiko.gecko_view_$id';
            _channel = MethodChannel(channelName);
            print(
                '[NyaNyaWebViewLog-Flutter] GeckoWebview: Created MethodChannel, name=$channelName, channel.hashCode=${identityHashCode(_channel!)}');

            // 创建通信接口
            _communication = GeckoCommunication(
              sessionId: widget.sessionId,
              channel: _channel!,
            );
            _communication?.setMessageHandler(widget.messageHandler);

            // 设置原始的 MethodCallHandler 以处理其他事件（onOpenUrl 等）
            _channel!.setMethodCallHandler(_actualHandleMethodCall);
            print(
                '[NyaNyaWebViewLog-Flutter] GeckoWebview: MethodCallHandler set (instance method)');

            widget.onChannelCreated?.call(_channel!);
            widget.onCommunicationCreated?.call(_communication!);

            print(
                '[NyaNyaWebViewLog-Flutter] GeckoWebview: Sending testCommunication to native NOW');
            _channel!.invokeMethod('testCommunication').then((result) {
              print(
                  '[NyaNyaWebViewLog-Flutter] GeckoWebview: testCommunication response received: $result');
            }).catchError((error) {
              print(
                  '[NyaNyaWebViewLog-Flutter] GeckoWebview: testCommunication error: $error');
            });

            loadUrl(_currentOptions.initialUrl);
            params.onPlatformViewCreated(id);
          });

          controller.create();
          return controller;
        },
      );
    }

    return const Center(
      child: Text('GeckoWebview is only supported on Android'),
    );
  }

  Future<dynamic> _actualHandleMethodCall(MethodCall call) async {
    try {
      switch (call.method) {
        case 'testCommunication':
          print(
              '[NyaNyaWebViewLog-Flutter] GeckoWebview: testCommunication received from native!');
          return {
            'status': 'ok',
            'message': 'Hello from Flutter GeckoWebview!',
            'time': DateTime.now().millisecondsSinceEpoch
          };
        case 'testNativeToFlutter':
          print(
              '[NyaNyaWebViewLog-Flutter] GeckoWebview: testNativeToFlutter received from native! args=${call.arguments}');
          return {'status': 'ok', 'received': true};
        case 'onWebMessage':
          final String message = call.arguments as String;
          print(
              '[NyaNyaWebViewLog-Flutter] GeckoWebview: onWebMessage received, message=$message');
          // 通过通信接口处理消息（与 SystemWebview 保持一致）
          _communication?.handleMessageFromWeb(message);
          widget.messageHandler(message);
          return {'status': 'ok'};
        case 'onTitleChange':
          final titleFromArgs = call.arguments['title'];
          final String title = titleFromArgs as String? ?? '';
          print(
              '[NyaNyaWebViewLog-Flutter] GeckoWebview: onTitleChange received, title=$title');
          widget.messageHandler(
              '{"type":"onTitleChange","payload":{"title":"$title"}}');
          return {'status': 'ok'};
        case 'onLocationChange':
          final urlFromArgs = call.arguments['url'];
          final String url = urlFromArgs as String? ?? '';
          print(
              '[NyaNyaWebViewLog-Flutter] GeckoWebview: onLocationChange received, url=$url');
          widget.messageHandler(
              '{"type":"onLocationChange","payload":{"url":"$url"}}');
          return {'status': 'ok'};
        case 'onPageStart':
          final urlFromArgs = call.arguments['url'];
          final String url = urlFromArgs as String? ?? '';
          print(
              '[NyaNyaWebViewLog-Flutter] GeckoWebview: onPageStart received, url=$url');
          widget.messageHandler(
              '{"type":"onPageStart","payload":{"url":"$url"}}');
          return {'status': 'ok'};
        case 'onPageStop':
          final successFromArgs = call.arguments['success'];
          final bool success = successFromArgs as bool? ?? false;
          print(
              '[NyaNyaWebViewLog-Flutter] GeckoWebview: onPageStop received, success=$success');

          widget.messageHandler(
              '{"type":"onPageStop","payload":{"success":$success}}');
          return {'status': 'ok'};
        case 'onOpenUrl':
          print(
              '[NyaNyaWebViewLog-Flutter] ========== onOpenUrl RECEIVED ==========');
          final urlFromArgs = call.arguments['url'];
          final targetFromArgs = call.arguments['target'];
          print(
              '[NyaNyaWebViewLog-Flutter] onOpenUrl raw args: url=$urlFromArgs (${urlFromArgs.runtimeType}), target=$targetFromArgs (${targetFromArgs.runtimeType})');

          final String url = urlFromArgs as String? ?? '';
          final String? target = targetFromArgs as String?;

          print(
              '[NyaNyaWebViewLog-Flutter] GeckoWebview: onOpenUrl parsed, url=$url, target=$target');
          print(
              '[NyaNyaWebViewLog-Flutter] GeckoWebview: _currentOptions.newTabBehavior = ${_currentOptions.newTabBehavior}');
          print(
              '[NyaNyaWebViewLog-Flutter] GeckoWebview: widget.onOpenUrl != null = ${widget.onOpenUrl != null}');

          if (_currentOptions.newTabBehavior == NewTabBehavior.delegate) {
            print(
                '[NyaNyaWebViewLog-Flutter] GeckoWebview: newTabBehavior is delegate');
            if (widget.onOpenUrl != null) {
              print(
                  '[NyaNyaWebViewLog-Flutter] GeckoWebview: Calling user onOpenUrl callback NOW!');
              widget.onOpenUrl!(url, target);
              print(
                  '[NyaNyaWebViewLog-Flutter] GeckoWebview: user onOpenUrl callback called!');
            } else {
              print(
                  '[NyaNyaWebViewLog-Flutter] GeckoWebview: WARNING - widget.onOpenUrl is NULL!');
            }
          } else {
            print(
                '[NyaNyaWebViewLog-Flutter] GeckoWebview: newTabBehavior is NOT delegate, loading url in current webview');
            loadUrl(url);
          }
          print(
              '[NyaNyaWebViewLog-Flutter] ========== onOpenUrl HANDLED ==========');
          return {'status': 'ok', 'url': url, 'target': target};
        case 'onRequestExitApp':
          print(
              '[NyaNyaWebViewLog-Flutter] GeckoWebview: onRequestExitApp received, closing current tab');
          if (widget.onClose != null) {
            widget.onClose!();
            print(
                '[NyaNyaWebViewLog-Flutter] GeckoWebview: onClose callback called');
          } else {
            print(
                '[NyaNyaWebViewLog-Flutter] GeckoWebview: WARNING - onClose is null, cannot close tab');
          }
          return {'status': 'ok'};
        default:
          print(
              '[NyaNyaWebViewLog-Flutter] GeckoWebview: Unknown method called: ${call.method}');
          return {'status': 'error', 'error': 'Unknown method'};
      }
    } catch (e, stack) {
      print(
          '[NyaNyaWebViewLog-Flutter] ========== ERROR IN _actualHandleMethodCall ==========');
      print(
          '[NyaNyaWebViewLog-Flutter] GeckoWebview: Error in _actualHandleMethodCall: $e');
      print('[NyaNyaWebViewLog-Flutter] GeckoWebview: Stack trace: $stack');
      print(
          '[NyaNyaWebViewLog-Flutter] =================================================');
      return {'status': 'error', 'error': e.toString()};
    }
  }

  Future<void> loadUrl(String url) async {
    if (_channel == null) {
      int attempts = 0;
      const maxAttempts = 50;
      while (_channel == null && attempts < maxAttempts) {
        await Future.delayed(const Duration(milliseconds: 100));
        attempts++;
      }
    }
    await _channel?.invokeMethod('loadUrl', {'url': url});
  }
}

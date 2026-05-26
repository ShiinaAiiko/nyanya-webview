import 'dart:async';
import 'dart:convert';

typedef BridgeMessageHandler = void Function(Map<String, dynamic> message);
typedef BridgeResponseCallback = void Function(dynamic data);

class WebViewBridge {
  final Map<String, List<BridgeMessageHandler>> _messageHandlers = {};
  final Map<String, Completer<dynamic>> _pendingResponses = {};
  final void Function(String message) _messageSender;
  
  int _messageIdCounter = 0;

  WebViewBridge({required void Function(String message) messageSender})
      : _messageSender = messageSender;

  void on(String eventName, BridgeMessageHandler handler) {
    _messageHandlers.putIfAbsent(eventName, () => []).add(handler);
  }

  void off(String eventName, BridgeMessageHandler handler) {
    _messageHandlers[eventName]?.remove(handler);
  }

  void handleMessage(String message) {
    try {
      print('handleMessage Received message: $message');
      final Map<String, dynamic> data = jsonDecode(message);
      final String type = data['type'] as String;
      final dynamic payload = data['payload'];
      final String? bridgeId = data['bridgeId'] as String?;

      if (bridgeId != null && _pendingResponses.containsKey(bridgeId)) {
        _pendingResponses[bridgeId]?.complete(payload);
        _pendingResponses.remove(bridgeId);
        return;
      }

      if (_messageHandlers.containsKey(type)) {
        for (final handler in _messageHandlers[type]!) {
          handler({'type': type, 'payload': payload});
        }
      }
    } catch (e) {
      print('Error parsing bridge message: $e');
    }
  }

  Future<dynamic> send(String type, dynamic payload) {
    final String bridgeId = 'msg_${++_messageIdCounter}_${DateTime.now().millisecondsSinceEpoch}';
    final completer = Completer<dynamic>();
    _pendingResponses[bridgeId] = completer;

    final message = jsonEncode({
      'type': type,
      'payload': payload,
      'bridgeId': bridgeId,
    });

    _messageSender(message);

    return completer.future;
  }

  void sendWithoutResponse(String type, dynamic payload) {
    final message = jsonEncode({
      'type': type,
      'payload': payload,
    });
    _messageSender(message);
  }

  void dispose() {
    _messageHandlers.clear();
    _pendingResponses.forEach((_, completer) => completer.completeError('Bridge disposed'));
    _pendingResponses.clear();
  }
}
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:uuid/uuid.dart';
import '../webview_options.dart';
import '../webview_controller.dart';
import '../webview_communication_interface.dart';

class TabInfo {
  final String id;
  final String url;
  final String title;
  final bool isCurrent;

  TabInfo({
    required this.id,
    required this.url,
    this.title = '',
    this.isCurrent = false,
  });

  TabInfo copyWith({
    String? url,
    String? title,
    bool? isCurrent,
  }) {
    return TabInfo(
      id: id,
      url: url ?? this.url,
      title: title ?? this.title,
      isCurrent: isCurrent ?? this.isCurrent,
    );
  }
}

class UrlChangeBroadcaster {
  static final UrlChangeBroadcaster _instance =
      UrlChangeBroadcaster._internal();
  factory UrlChangeBroadcaster() => _instance;
  UrlChangeBroadcaster._internal();

  final StreamController<UrlChangeEvent> _controller =
      StreamController<UrlChangeEvent>.broadcast();

  Stream<UrlChangeEvent> get stream => _controller.stream;

  void broadcast(UrlChangeEvent event) {
    _controller.add(event);
  }

  void dispose() {
    _controller.close();
  }
}

class UrlChangeEvent {
  final String url;
  final String title;

  UrlChangeEvent({required this.url, this.title = ''});
}

class TabManager extends ChangeNotifier {
  final WebViewOptions Function(String url) _optionsBuilder;
  final int maxTabs;
  final bool _enableTabBarByDefault;

  final List<TabInfo> _tabs = [];
  int _currentIndex = -1;

  void Function(String tabId, String title)? onTitleChanged;
  void Function(String tabId, String url)? onUrlChanged;
  void Function(String url, String? target)? onOpenUrl;
  void Function(String tabId, String message)? onMessage;
  void Function(String tabId, dynamic channel)? onChannelCreated;
  void Function(String tabId, IWebViewCommunication)? onCommunicationCreated;
  void Function(String tabId)? onTabClosed;

  TabManager({
    required WebViewOptions Function(String url) optionsBuilder,
    this.maxTabs = 10,
    bool enableTabBarByDefault = true,
  })  : _optionsBuilder = optionsBuilder,
        _enableTabBarByDefault = enableTabBarByDefault;

  List<TabInfo> get tabs => List.unmodifiable(_tabs);
  int get currentIndex => _currentIndex;
  int get tabCount => _tabs.length;
  bool get hasMultipleTabs => _tabs.length > 1;
  bool get enableTabBar => _enableTabBarByDefault && _tabs.length > 1;

  TabInfo? get currentTab {
    if (_currentIndex < 0 || _currentIndex >= _tabs.length) {
      return null;
    }
    return _tabs[_currentIndex];
  }

  String generateTabId() {
    return const Uuid().v4();
  }

  TabInfo openTab(String url, {String? title}) {
    if (_tabs.length >= maxTabs) {
      _closeTab(0);
    }

    final id = generateTabId();
    final tab = TabInfo(
      id: id,
      url: url,
      title: title ?? '',
      isCurrent: true,
    );

    for (int i = 0; i < _tabs.length; i++) {
      _tabs[i] = _tabs[i].copyWith(isCurrent: false);
    }

    _tabs.add(tab);
    _currentIndex = _tabs.length - 1;

    notifyListeners();
    return tab;
  }

  void closeTab(String tabId) {
    final index = _tabs.indexWhere((t) => t.id == tabId);
    if (index >= 0) {
      _closeTab(index);
    }
  }

  void _closeTab(int index) {
    if (index < 0 || index >= _tabs.length) return;

    _tabs.removeAt(index);

    if (_tabs.isEmpty) {
      _currentIndex = -1;
    } else if (_currentIndex >= _tabs.length) {
      _currentIndex = _tabs.length - 1;
    } else if (index < _currentIndex) {
      _currentIndex--;
    }

    if (_currentIndex >= 0 && _currentIndex < _tabs.length) {
      for (int i = 0; i < _tabs.length; i++) {
        _tabs[i] = _tabs[i].copyWith(isCurrent: i == _currentIndex);
      }
    }

    notifyListeners();
  }

  void switchToTab(int index) {
    if (index < 0 || index >= _tabs.length || index == _currentIndex) return;

    for (int i = 0; i < _tabs.length; i++) {
      _tabs[i] = _tabs[i].copyWith(isCurrent: i == index);
    }
    _currentIndex = index;

    notifyListeners();
  }

  void replaceCurrentTab(String url, {String? title}) {
    if (_currentIndex < 0 || _currentIndex >= _tabs.length) return;

    _tabs[_currentIndex] = _tabs[_currentIndex].copyWith(
      url: url,
      title: title ?? '',
    );

    notifyListeners();
  }

  void updateTabTitle(String tabId, String title) {
    final index = _tabs.indexWhere((t) => t.id == tabId);
    if (index >= 0) {
      _tabs[index] = _tabs[index].copyWith(title: title);
      notifyListeners();
    }
  }

  void updateTabUrl(String tabId, String url) {
    final index = _tabs.indexWhere((t) => t.id == tabId);
    if (index >= 0) {
      _tabs[index] = _tabs[index].copyWith(url: url);
      notifyListeners();
    }
  }

  void clearAllTabs() {
    _tabs.clear();
    _currentIndex = -1;
    notifyListeners();
  }

  WebViewOptions buildOptions(String url) {
    return _optionsBuilder(url);
  }

  WebViewOptions? getTabOptions(String tabId) {
    final index = _tabs.indexWhere((t) => t.id == tabId);
    if (index < 0) return null;
    return _optionsBuilder(_tabs[index].url);
  }
}

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../webview_options.dart';
import '../webview_controller.dart';
import '../webview_communication_interface.dart';
import 'tab_manager.dart';

class _TabPageI18n {
  static final Map<String, Map<String, String>> _translations = {
    'zh-CN': {
      'share': '分享',
      'url_copied': '已复制URL',
      'copy_failed': '复制失败',
      'loading': '加载中...',
    },
    'zh-TW': {
      'share': '分享',
      'url_copied': '已複製URL',
      'copy_failed': '複製失敗',
      'loading': '載入中...',
    },
    'en-US': {
      'share': 'Share',
      'url_copied': 'URL copied',
      'copy_failed': 'Copy failed',
      'loading': 'Loading...',
    },
  };

  static String t(String key, {String? language}) {
    final targetLanguage = language ?? 'en-US';
    if (_translations.containsKey(targetLanguage)) {
      return _translations[targetLanguage]![key] ?? key;
    }
    final languageOnly = targetLanguage.split('-').first;
    for (final localeKey in _translations.keys) {
      if (localeKey.startsWith('$languageOnly-')) {
        return _translations[localeKey]![key] ?? key;
      }
    }
    return _translations['en-US']![key] ?? key;
  }
}

class TabPage extends StatefulWidget {
  final String tabId;
  final String url;
  final WebViewOptions options;
  final void Function(String tabId, String title)? onTitleChanged;
  final void Function(String tabId, String url)? onUrlChanged;
  final OpenUrlHandler? onOpenUrl;
  final VoidCallback? onClose;
  final String? language;
  final void Function(String tabId, String message)? onMessage;
  final void Function(String tabId, dynamic channel)? onChannelCreated;
  final void Function(String tabId, IWebViewCommunication)?
      onCommunicationCreated;
  final void Function(String tabId)? onTabClosed;

  const TabPage({
    super.key,
    required this.tabId,
    required this.url,
    required this.options,
    this.onTitleChanged,
    this.onUrlChanged,
    this.onOpenUrl,
    this.onClose,
    this.language,
    this.onMessage,
    this.onChannelCreated,
    this.onCommunicationCreated,
    this.onTabClosed,
  });

  @override
  State<TabPage> createState() => _TabPageState();
}

class _TabPageState extends State<TabPage> {
  late NyaNyaWebViewController _controller;
  String _currentUrl = '';
  String _currentTitle = '';
  bool _isLoading = true;

  bool _canGoBack = false;
  bool _canGoForward = false;

  final GlobalKey<ScaffoldMessengerState> _scaffoldMessengerKey =
      GlobalKey<ScaffoldMessengerState>();

  @override
  void initState() {
    super.initState();
    _currentUrl = widget.url;
    _initController();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _updateNavigationState();
    });
  }

  void _initController() {
    _controller =
        NyaNyaWebViewController(widget.options, sessionId: widget.tabId);
    _controller.setOnOpenUrlHandler((url, target) {
      widget.onOpenUrl?.call(url, target);
    });
    _controller.setOnCloseHandler(() {
      widget.onClose?.call();
    });

    _controller.onMessage = (sessionId, message) {
      widget.onMessage?.call(widget.tabId, message);
    };

    _controller.onChannelCreated = (sessionId, channel) {
      print('[TabPage] Channel created for session: $sessionId');
      widget.onChannelCreated?.call(sessionId, channel);
    };

    _controller.onCommunicationCreated = (sessionId, communication) {
      print('[TabPage] Communication created for session: $sessionId');
      widget.onCommunicationCreated?.call(sessionId, communication);
    };

    _controller.on('onTitleChange', (message) {
      final payload = message['payload'] as Map<String, dynamic>?;
      final title = payload?['title'] as String? ?? '';
      if (mounted) {
        setState(() {
          _currentTitle = title;
        });
        widget.onTitleChanged?.call(widget.tabId, title);
        _updateNavigationState();
      }
    });

    _controller.on('onLocationChange', (message) {
      final payload = message['payload'] as Map<String, dynamic>?;
      final url = payload?['url'] as String? ?? '';
      print('onLocationChange: $url, mounted: $mounted');
      if (mounted && url != "about:blank") {
        setState(() {
          _currentUrl = url;
        });
        widget.onUrlChanged?.call(widget.tabId, url);
        _updateNavigationState();
      }
    });

    _controller.on('onPageStart', (message) {
      final payload = message['payload'] as Map<String, dynamic>?;
      final url = payload?['url'] as String? ?? '';
      if (mounted) {
        setState(() {
          _currentUrl = url;
        });
        widget.onUrlChanged?.call(widget.tabId, url);
      }
    });
  }

  @override
  void dispose() {
    widget.onTabClosed?.call(widget.tabId);
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ScaffoldMessenger(
      key: _scaffoldMessengerKey,
      child: Scaffold(
        appBar: AppBar(
          title: _buildTitle(),
          centerTitle: false,
          leading: IconButton(
            icon: const Icon(Icons.close),
            onPressed: () {
              Navigator.of(context).pop();
            },
          ),
          actions: [
            _buildDropdownMenu(),
          ],
        ),
        body: _buildWebView(),
      ),
    );
  }

  Widget _buildTitle() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Text(
          _currentTitle.isNotEmpty
              ? _currentTitle
              : _TabPageI18n.t('loading', language: widget.language),
          style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w500),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        const SizedBox(height: 2),
        Text(
          _currentUrl.isNotEmpty ? _getDisplayUrl(_currentUrl) : '',
          style: const TextStyle(fontSize: 12, color: Colors.grey),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
      ],
    );
  }

  Widget _buildDropdownMenu() {
    return PopupMenuButton<String>(
      key: ValueKey('menu-$_canGoBack-$_canGoForward'),
      icon: const Icon(Icons.more_vert, size: 24),
      onSelected: (value) {
        switch (value) {
          case 'back':
            _handleGoBack();
            break;
          case 'forward':
            _handleGoForward();
            break;
          case 'refresh':
            _handleRefresh();
            break;
          case 'share':
            _handleShare();
            break;
        }
      },
      itemBuilder: (BuildContext context) => [
        PopupMenuItem<String>(
          value: 'placeholder1',
          enabled: true,
          padding: EdgeInsets.zero,
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              IconButton(
                icon: const Icon(Icons.arrow_back, size: 20),
                onPressed: _canGoBack
                    ? () {
                        Navigator.pop(context);
                        _handleGoBack();
                      }
                    : null,
                disabledColor: Colors.grey,
              ),
              IconButton(
                icon: const Icon(Icons.arrow_forward, size: 20),
                onPressed: _canGoForward
                    ? () {
                        Navigator.pop(context);
                        _handleGoForward();
                      }
                    : null,
                disabledColor: Colors.grey,
              ),
              IconButton(
                icon: const Icon(Icons.refresh, size: 20),
                color: Colors.white,
                onPressed: () {
                  Navigator.pop(context);
                  _handleRefresh();
                },
              ),
            ],
          ),
        ),
        const PopupMenuDivider(),
        PopupMenuItem<String>(
          value: 'share',
          child: Row(
            children: [
              const Icon(Icons.share, size: 20),
              const SizedBox(width: 8),
              Text(_TabPageI18n.t('share', language: widget.language)),
            ],
          ),
        ),
      ],
    );
  }

  Future<void> _handleGoBack() async {
    await _controller.goBack();
    _updateNavigationState();
  }

  Future<void> _handleGoForward() async {
    await _controller.goForward();
    _updateNavigationState();
  }

  Future<void> _handleRefresh() async {
    print('[NyaNyaWebViewLog] _handleRefresh');
    await _controller.reload();
  }

  Future<void> _handleShare() async {
    var urlToShare = _currentUrl.isNotEmpty ? _currentUrl : widget.url;
    if (urlToShare.isEmpty) return;

    urlToShare = widget.options.applyUrlRewrite(urlToShare);

    try {
      await Clipboard.setData(ClipboardData(text: urlToShare));
      if (mounted) {
        _scaffoldMessengerKey.currentState?.showSnackBar(
          SnackBar(
            content: Text(
              _TabPageI18n.t('url_copied', language: widget.language),
              style: const TextStyle(color: Colors.white),
            ),
            duration: const Duration(seconds: 2),
            behavior: SnackBarBehavior.floating,
            margin: const EdgeInsets.only(bottom: 120, left: 20, right: 20),
            backgroundColor: Colors.black87,
            elevation: 8,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        _scaffoldMessengerKey.currentState?.showSnackBar(
          SnackBar(
            content: Text(
              _TabPageI18n.t('copy_failed', language: widget.language),
              style: const TextStyle(color: Colors.white),
            ),
            duration: const Duration(seconds: 2),
            behavior: SnackBarBehavior.floating,
            margin: const EdgeInsets.only(bottom: 120, left: 20, right: 20),
            backgroundColor: Colors.black87,
            elevation: 8,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
          ),
        );
      }
    }
  }

  Future<void> _updateNavigationState() async {
    print(
        '[DEBUG] _updateNavigationState called, _controller: $_controller, mounted: $mounted');
    final canGoBack = await _controller.canGoBack();
    final canGoForward = await _controller.canGoForward();

    print('onLocationChange updateNavigationState: $canGoBack, $canGoForward');
    setState(() {
      _canGoBack = canGoBack;
      _canGoForward = canGoForward;
    });
  }

  Widget _buildWebView() {
    return Column(
      children: [
        Expanded(
          child: _controller.build(context),
        ),
      ],
    );
  }

  String _getDisplayUrl(String url) {
    String processedUrl = widget.options.applyUrlRewrite(url);
    if (processedUrl.endsWith('/')) {
      processedUrl = processedUrl.substring(0, processedUrl.length - 1);
    }
    if (processedUrl.startsWith('https://')) {
      return processedUrl.substring(8);
    }
    if (processedUrl.startsWith('http://')) {
      return processedUrl.substring(7);
    }
    return processedUrl;
  }
}

class TabPageRoute<T> extends MaterialPageRoute<T> {
  final String tabId;
  final String url;

  TabPageRoute({
    required this.tabId,
    required this.url,
    required WidgetBuilder builder,
  }) : super(builder: builder);

  @override
  Widget buildContent(BuildContext context) {
    return builder(context);
  }
}

void navigateToTab({
  required BuildContext context,
  required TabManager tabManager,
  required String tabId,
  required String url,
}) {
  Navigator.of(context).push(
    TabPageRoute(
      tabId: tabId,
      url: url,
      builder: (context) => TabPage(
        tabId: tabId,
        url: url,
        options: tabManager.getTabOptions(tabId) ??
            const WebViewOptions(initialUrl: ''),
        onTitleChanged: tabManager.onTitleChanged,
        onUrlChanged: tabManager.onUrlChanged,
        onOpenUrl: tabManager.onOpenUrl,
        onClose: () => tabManager.closeTab(tabId),
        onMessage: tabManager.onMessage,
        onChannelCreated: tabManager.onChannelCreated,
        onCommunicationCreated: tabManager.onCommunicationCreated,
        onTabClosed: tabManager.onTabClosed,
      ),
    ),
  );
}

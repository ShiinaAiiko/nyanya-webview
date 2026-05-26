import 'package:flutter/material.dart';
import '../webview_options.dart';
import '../webview_controller.dart';
import '../webview_bridge.dart';
import '../webview_communication_interface.dart';
import 'tab_manager.dart';
import 'tab_page.dart';

class TabManagerWidget extends StatefulWidget {
  final String initialUrl;
  final WebViewOptions Function(String url) optionsBuilder;
  final int maxTabs;
  final bool showTabBar;
  final Widget? loadingWidget;
  final Brightness? brightness;
  final void Function(WebViewBridge bridge)? onBridgeReady;
  final String? language;
  final void Function(String tabId, String message)? onMessage;
  final void Function(String tabId, dynamic channel)? onChannelCreated;
  final void Function(String tabId, IWebViewCommunication)?
      onCommunicationCreated;
  final void Function(String tabId)? onTabClosed;

  const TabManagerWidget({
    super.key,
    required this.initialUrl,
    required this.optionsBuilder,
    this.maxTabs = 10,
    this.showTabBar = true,
    this.loadingWidget,
    this.brightness,
    this.onBridgeReady,
    this.language,
    this.onMessage,
    this.onChannelCreated,
    this.onCommunicationCreated,
    this.onTabClosed,
  });

  @override
  State<TabManagerWidget> createState() => _TabManagerWidgetState();
}

class _TabManagerWidgetState extends State<TabManagerWidget> {
  late TabManager _tabManager;
  NyaNyaWebViewController? _currentController;
  bool _isLoading = true;

  Future<bool> _handleBackPress() async {
    print('[NyaNyaWebViewLog] TabManagerWidget._handleBackPress called');
    if (_currentController != null) {
      final canGoBack = await _currentController!.canGoBack();
      print(
          '[NyaNyaWebViewLog] TabManagerWidget._handleBackPress: canGoBack=$canGoBack');
      if (canGoBack) {
        await _currentController!.goBack();
        return false;
      }
    }
    Navigator.of(context).pop();
    return false;
  }

  @override
  void initState() {
    super.initState();
    _tabManager = TabManager(
      optionsBuilder: widget.optionsBuilder,
      maxTabs: widget.maxTabs,
      enableTabBarByDefault: widget.showTabBar,
    );
    _tabManager.addListener(_onTabManagerChanged);
    _openInitialTab();
  }

  void _openInitialTab() {
    _tabManager.openTab(widget.initialUrl);
  }

  void _onTabManagerChanged() {
    setState(() {});
  }

  @override
  void dispose() {
    _tabManager.removeListener(_onTabManagerChanged);
    _currentController?.dispose();
    super.dispose();
  }

  void _handleOpenUrl(String url, String? target) {
    Navigator.of(context).push(
      PageRouteBuilder(
        pageBuilder: (context, animation, secondaryAnimation) =>
            TabManagerWidget(
          initialUrl: url,
          optionsBuilder: widget.optionsBuilder,
          maxTabs: widget.maxTabs,
          showTabBar: widget.showTabBar,
          loadingWidget: widget.loadingWidget,
          brightness: widget.brightness,
          onBridgeReady: widget.onBridgeReady,
          language: widget.language,
          onMessage: widget.onMessage,
          onChannelCreated: widget.onChannelCreated,
          onCommunicationCreated: widget.onCommunicationCreated,
          onTabClosed: widget.onTabClosed,
        ),
        transitionsBuilder: (context, animation, secondaryAnimation, child) {
          const begin = Offset(1.0, 0.0);
          const end = Offset.zero;
          const curve = Curves.easeInOut;
          var tween =
              Tween(begin: begin, end: end).chain(CurveTween(curve: curve));
          return SlideTransition(
            position: animation.drive(tween),
            child: child,
          );
        },
        transitionDuration: const Duration(milliseconds: 300),
        reverseTransitionDuration: const Duration(milliseconds: 300),
      ),
    );
  }

  String _getDisplayUrl(String url) {
    final options = widget.optionsBuilder(url);
    String processedUrl = options.applyUrlRewrite(url);
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

  @override
  Widget build(BuildContext context) {
    final brightness = widget.brightness ?? Brightness.light;
    final textColor =
        brightness == Brightness.dark ? Colors.white : Colors.black;
    final subTextColor =
        brightness == Brightness.dark ? Colors.white70 : Colors.black54;
    final backgroundColor =
        brightness == Brightness.dark ? const Color(0xFF202124) : Colors.white;

    if (_tabManager.tabCount == 0) {
      return widget.loadingWidget ??
          const Center(child: CircularProgressIndicator());
    }

    return WillPopScope(
      onWillPop: _handleBackPress,
      child: Scaffold(
        body: Column(
          children: [
            if (widget.showTabBar && _tabManager.hasMultipleTabs)
              _buildTabBar(
                  brightness, textColor, subTextColor, backgroundColor),
            Expanded(
              child: _buildCurrentTabContent(),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTabBar(
    Brightness brightness,
    Color textColor,
    Color subTextColor,
    Color backgroundColor,
  ) {
    return Container(
      color: backgroundColor,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox(
            height: 48,
            child: ListView.builder(
              scrollDirection: Axis.horizontal,
              itemCount: _tabManager.tabCount,
              itemBuilder: (context, index) {
                final tab = _tabManager.tabs[index];
                return _buildTabItem(
                    tab, textColor, subTextColor, backgroundColor);
              },
            ),
          ),
          Divider(height: 1, color: subTextColor.withOpacity(0.2)),
        ],
      ),
    );
  }

  Widget _buildTabItem(
    TabInfo tab,
    Color textColor,
    Color subTextColor,
    Color backgroundColor,
  ) {
    final isSelected = tab.isCurrent;
    return GestureDetector(
      onTap: () => _tabManager.switchToTab(_tabManager.tabs.indexOf(tab)),
      child: Container(
        constraints: const BoxConstraints(maxWidth: 200),
        padding: const EdgeInsets.symmetric(horizontal: 12),
        decoration: BoxDecoration(
          color:
              isSelected ? backgroundColor : backgroundColor.withOpacity(0.5),
          border: Border(
            bottom: BorderSide(
              color: isSelected ? Colors.blue : Colors.transparent,
              width: 2,
            ),
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Flexible(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    tab.title.isNotEmpty ? tab.title : _getDisplayUrl(tab.url),
                    style: TextStyle(
                      color: textColor,
                      fontSize: 13,
                      fontWeight:
                          isSelected ? FontWeight.w500 : FontWeight.normal,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  if (tab.title.isNotEmpty)
                    Text(
                      _getDisplayUrl(tab.url),
                      style: TextStyle(
                        color: subTextColor,
                        fontSize: 11,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            GestureDetector(
              onTap: () {
                final closingTabId = tab.id;
                widget.onTabClosed?.call(closingTabId);
                if (_tabManager.tabCount == 1) {
                  _tabManager.closeTab(tab.id);
                  Navigator.of(context).pop();
                } else {
                  _tabManager.closeTab(tab.id);
                }
              },
              child: Icon(
                Icons.close,
                size: 18,
                color: subTextColor,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildCurrentTabContent() {
    final currentTab = _tabManager.currentTab;
    if (currentTab == null) {
      return widget.loadingWidget ??
          const Center(child: CircularProgressIndicator());
    }

    return TabPage(
      key: ValueKey(currentTab.id),
      tabId: currentTab.id,
      url: currentTab.url,
      options: _tabManager.buildOptions(currentTab.url),
      onOpenUrl: _handleOpenUrl,
      onClose: () {
        Navigator.of(context).pop();
      },
      onTitleChanged: (tabId, title) {
        _tabManager.updateTabTitle(tabId, title);
      },
      onUrlChanged: (tabId, url) {
        _tabManager.updateTabUrl(tabId, url);
      },
      language: widget.language,
      onMessage: widget.onMessage,
      onChannelCreated: widget.onChannelCreated,
      onCommunicationCreated: widget.onCommunicationCreated,
      onTabClosed: widget.onTabClosed,
    );
  }
}

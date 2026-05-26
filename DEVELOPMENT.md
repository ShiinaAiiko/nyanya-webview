# nyanya_webview 模块开发文档

## 概述

`nyanya_webview` 是一个灵活的 Flutter WebView 包装库，支持 GeckoView 和系统 WebView 两种渲染引擎的切换。该库提供了统一的 API 接口，使应用层可以无缝切换 WebView 引擎。

## 功能特性

- **双核引擎支持**：支持 GeckoView 和系统 WebView
- **统一 API**：通过抽象接口提供一致的 WebView 操作
- **标签页管理**：内置标签页管理功能（详见 tab_manager 模块）
- **JavaScript Bridge**：完整的 Flutter ↔ WebView 双向通信机制
- **新页面拦截**：支持拦截 `window.open` 和 `<a target="_blank">` 等新开页面操作
- **标题/URL 联动**：支持 WebView 页面标题和 URL 变化事件回调
- **MethodChannel 通信**：Flutter 与原生端双向通信
- **sessionId 机制**：支持多标签页 JS Bridge 隔离
- **UUID 生成**：使用标准 UUID v4 生成 sessionId
- **onChannelCreated 回调**：获取 MethodChannel 实例
- **导航状态支持**：完整的 canGoBack/canGoForward 实现

## 目录结构

```
nyanya_webview/
├── android/
│   └── src/main/kotlin/club/aiiko/nyanya_webview/
│       ├── NyanyaWebviewPlugin.kt       # 插件入口
│       ├── GeckoViewFactory.kt          # GeckoView PlatformView 工厂
│       ├── GeckoViewPlatform.kt         # GeckoView 原生实现
│       ├── SystemWebViewFactory.kt      # 系统 WebView PlatformView 工厂
│       └── SystemWebViewPlatform.kt     # 系统 WebView 原生实现
├── lib/
│   ├── nyanya_webview.dart              # 模块导出文件
│   └── src/
│       ├── webview_interface.dart       # WebView 抽象接口
│       ├── webview_options.dart         # WebView 配置选项
│       ├── webview_controller.dart      # WebView 控制器
│       ├── webview_bridge.dart          # JavaScript Bridge
│       ├── gecko_webview.dart           # GeckoView 实现
│       ├── system_webview.dart          # 系统 WebView 实现
│       └── tab_manager/                 # 标签页管理模块（单独文档）
└── pubspec.yaml
```

## 核心组件

### 1. WebViewInterface - 抽象接口

**文件**：`lib/src/webview_interface.dart`

定义了 WebView 的标准操作接口，所有 WebView 实现都必须遵守该接口。

```dart
abstract class WebViewInterface {
  Widget build(BuildContext context);
  Future<void> loadUrl(String url);
  Future<void> reload();
  Future<void> goBack();
  Future<void> goForward();
  Future<bool> canGoBack();
  Future<bool> canGoForward();
  Future<void> evaluateJavascript(String script);
  Future<void> postMessage(String message);
  Future<void> setWebMessageHandler(WebViewMessageHandler handler);
  Future<void> openInBrowser(String url);
  Future<void> dispose();
}
```

### 2. WebViewOptions - 配置选项

**文件**：`lib/src/webview_options.dart`

WebView 的配置类，包含引擎选择、新标签页行为、URL 替换规则等核心配置。

```dart
enum WebViewEngine {
  gecko,    // 使用 GeckoView 引擎
  system,   // 使用系统 WebView 引擎
}

enum NewTabBehavior {
  replace,  // 在当前 WebView 中替换
  delegate, // 委托给 Flutter 层处理
}

typedef OpenUrlHandler = void Function(String url, String? target);

class UrlRewriteRule {
  final RegExp pattern;     // URL 匹配正则
  final String replacement; // 替换目标

  const UrlRewriteRule({
    required this.pattern,
    required this.replacement,
  });

  String apply(String url) {
    return url.replaceAll(pattern, replacement);
  }
}

class WebViewOptions {
  final WebViewEngine engine;
  final String initialUrl;
  final bool enableJavascript;
  final bool enableGeolocation;
  final bool enableMixedContent;
  final int? serverPort;
  final Map<String, String>? headers;
  final NewTabBehavior newTabBehavior;
  final List<UrlRewriteRule>? urlRewriteRules;

  String applyUrlRewrite(String url) {
    if (urlRewriteRules == null || urlRewriteRules!.isEmpty) {
      return url;
    }
    String result = url;
    for (final rule in urlRewriteRules!) {
      result = rule.apply(result);
    }
    return result;
  }
}
```

**配置示例**：

```dart
final options = WebViewOptions(
  engine: WebViewEngine.gecko,
  initialUrl: 'https://example.com',
  serverPort: 13218,
  newTabBehavior: NewTabBehavior.delegate,
  urlRewriteRules: [
    UrlRewriteRule(
      pattern: RegExp(r'https?://(localhost|127\.0\.0\.1):13218'),
      replacement: 'https://production.example.com',
    ),
  ],
);
```

### 3. WebViewController - 控制器

**文件**：`lib/src/webview_controller.dart`

WebView 的控制器类，封装了 WebView 的所有操作，提供统一的 API。

主要功能：
- 根据配置选择 WebView 引擎
- 封装 WebView 操作（加载、前进、后退、刷新等）
- 管理 JavaScript Bridge
- 处理新标签页回调

使用示例：
```dart
final controller = WebViewController(WebViewOptions(
  engine: WebViewEngine.gecko,
  initialUrl: 'https://example.com',
  serverPort: 13218,
  newTabBehavior: NewTabBehavior.delegate,
));

controller.setOnOpenUrlHandler((url, target) {
  // 处理新开页面
});
```

### 4. WebViewBridge - JavaScript 桥接

**文件**：`lib/src/webview_bridge.dart`

Flutter 与 WebView 之间的双向通信桥接器。

主要功能：
- 消息收发
- 事件订阅/取消订阅
- 请求-响应机制（带 bridgeId）

使用示例：
```dart
// 监听消息
bridge.on('myEvent', (message) {
  print('Received: ${message['payload']}');
});

// 发送消息并等待响应
final response = await bridge.send('getData', {'id': 123});

// 发送消息不等待响应
bridge.sendWithoutResponse('notify', {'type': 'info'});
```

**消息格式**：
```json
{
  "type": "eventName",
  "payload": { ... },
  "bridgeId": "msg_123_456789"  // 可选，用于请求-响应
}
```

### 5. GeckoWebview - GeckoView 实现

**文件**：`lib/src/gecko_webview.dart` 和 `android/src/main/kotlin/.../GeckoViewPlatform.kt`

GeckoView 引擎的 Flutter 和 Android 原生实现。

**Flutter 端**：
- PlatformView 集成（使用 Hybrid Composition 模式）
- MethodChannel 通信
- onOpenUrl 回调处理
- 标题/URL 变化事件转发

**Android 端**：
- GeckoView 初始化和配置
- GeckoSession 管理
- onNewSession 拦截（用于新开页面）
- JavaScript 执行
- 消息收发
- 标题/URL 变化监听

**MethodChannel 事件处理**：

| 方法 | 说明 |
|------|------|
| `testCommunication` | 测试通信连通性 |
| `onWebMessage` | WebView 发送的 JavaScript 消息 |
| `onTitleChange` | 页面标题变化 |
| `onPageStart` | 页面开始加载 |
| `onPageStop` | 页面加载完成 |
| `onOpenUrl` | 拦截到新开页面请求 |
| `onRequestExitApp` | WebView 无法后退，请求退出 |

**新页面拦截流程**：
```
用户点击新链接
  ↓
GeckoView.onNewSession() 触发
  ↓
MethodChannel.invokeMethod('onOpenUrl', params)
  ↓
Flutter 端 _actualHandleMethodCall() 接收
  ↓
根据 newTabBehavior 决定：
  - replace → 直接加载到当前 WebView
  - delegate → 调用 widget.onOpenUrl()
```

**标题/URL 联动流程**：
```
原生端 (GeckoSession)
  ↓ onTitleChange / onPageStart 事件
MethodChannel.invokeMethod('onTitleChange' / 'onPageStart')
  ↓
Flutter 端 _actualHandleMethodCall() 接收
  ↓
widget.messageHandler() 转发消息
  ↓
WebViewBridge.handleMessage() 解析
  ↓
TabPage._handleMessage() 处理
  ↓
setState() 更新 UI
```

### 6. SystemWebview - 系统 WebView 实现

**文件**：`lib/src/system_webview.dart` 和 `android/src/main/kotlin/.../SystemWebViewPlatform.kt`

系统 WebView 引擎的 Flutter 和 Android 原生实现。

**状态**：✅ 已完成

## 使用指南

### 基本使用

```dart
import 'package:nyanya_webview/nyanya_webview.dart';

// 1. 创建配置
final options = WebViewOptions(
  engine: WebViewEngine.gecko,
  initialUrl: 'https://example.com',
  serverPort: 13218,
  newTabBehavior: NewTabBehavior.delegate,
);

// 2. 创建控制器
final controller = WebViewController(options);

// 3. 配置回调
controller.setOnOpenUrlHandler((url, target) {
  // 处理新开页面
  print('Open new URL: $url, target: $target');
});

// 4. 注册 Bridge 事件
controller.on('myEvent', (message) {
  print('Received event: $message');
});

// 5. 构建 Widget
@override
Widget build(BuildContext context) {
  return controller.build(context);
}

// 6. 操作 WebView
controller.loadUrl('https://new-url.com');
controller.reload();
controller.goBack();

// 7. 发送消息到 WebView
await controller.send('setData', {'key': 'value'});
```

### 与 TabManager 配合使用

```dart
import 'package:nyanya_webview/nyanya_webview.dart';

TabManagerWidget(
  initialUrl: 'https://example.com',
  optionsBuilder: (url) => WebViewOptions(
    engine: WebViewEngine.gecko,
    initialUrl: url,
    serverPort: 13218,
    newTabBehavior: NewTabBehavior.delegate,
  ),
  maxTabs: 10,
  language: 'zh-CN',  // 可选，默认 en-US
  onBridgeReady: (bridge) {
    // Bridge 就绪回调
  },
)
```

## 开发指南

### 添加新的 WebView 引擎

1. 实现 `WebViewInterface` 接口
2. 在 `webview_controller.dart` 中添加引擎选择逻辑
3. 创建对应的 Android PlatformView 实现

### 扩展 WebViewOptions

1. 在 `webview_options.dart` 中添加新字段
2. 更新 `copyWith()` 方法
3. 在 WebView 实现中应用新配置

### 调试 Tips

- 使用 `NyaNyaWebViewLog` 日志标签过滤 onOpenUrl 相关日志
- 使用 `adb logcat | grep NyaNyaWebViewLog` 查看标签页相关日志
- 在 `GeckoViewPlatform.kt` 和 `gecko_webview.dart` 中添加调试日志
- 标题/URL 变化可通过日志 `[NyaNyaWebViewLog-Flutter] GeckoWebview: onTitleChange received` 查看

## 当前开发状态

| 功能 | 状态 |
|------|------|
| GeckoView 引擎实现 | ✅ 已完成 |
| 系统 WebView 引擎实现 | ✅ 已完成 |
| WebViewInterface 接口 | ✅ 已完成 |
| WebViewOptions 配置 | ✅ 已完成 |
| WebViewController 控制器 | ✅ 已完成 |
| WebViewBridge 桥接 | ✅ 已完成 |
| onOpenUrl 回调机制 | ✅ 已完成 |
| MethodChannel 通信 | ✅ 已完成 |
| 新页面拦截（GeckoView）| ✅ 已完成 |
| 新页面拦截（System WebView）| ✅ 已完成 |
| 标题/URL 联动（GeckoView）| ✅ 已完成 |
| sessionId 机制 | ✅ 已完成 |
| UUID 生成 | ✅ 已完成 |
| onChannelCreated 回调 | ✅ 已完成 |
| 导航状态（canGoBack/canGoForward）| ✅ 已完成 |

## 相关文档

- [tab_manager 模块开发文档](./lib/src/tab_manager/DEVELOPMENT.md)
- 项目根目录 context.md

## 维护者

NyaNya 开发团队

# nyanya_webview

Flutter WebView 包装库，支持 GeckoView 和系统 WebView 双引擎切换。

## 特性

- **双引擎支持** - GeckoView / 系统 WebView 一键切换
- **标签页管理** - 内置多标签页浏览功能
- **JavaScript Bridge** - Flutter ↔ WebView 双向通信
- **新页面拦截** - 自动处理 `window.open` 和 `_blank` 链接
- **URL 规则替换** - 通过正则配置域名映射
- **国际化支持** - 内置 zh-CN / zh-TW / en-US
- **灵活配置** - 支持多种 WebView 选项和自定义行为

## 安装

```yaml
dependencies:
  nyanya_webview:
    path: modules/nyanya_webview
```

### Android 配置

由于 GeckoView 依赖来自 Mozilla 官方 Maven 仓库，您需要在主项目中添加以下配置：

**1. 项目级 build.gradle (android/build.gradle)**

```gradle
allprojects {
    repositories {
        google()
        mavenCentral()
        // 添加 Mozilla Maven 仓库以获取 GeckoView
        maven {
            url "https://maven.mozilla.org/maven2/"
        }
    }
}
```

**2. 应用级 build.gradle (android/app/build.gradle)**

```gradle
repositories {
    google()
    mavenCentral()
    // 添加 Mozilla Maven 仓库以获取 GeckoView
    maven { url "https://maven.mozilla.org/maven2/" }
}
```

**3. 最低 SDK 版本要求**

GeckoView 要求最低 SDK 版本为 24，因此需要确保：

```gradle
android {
    defaultConfig {
        minSdkVersion 24
    }
}
```

## 快速开始

### 基本使用

```dart
import 'package:nyanya_webview/nyanya_webview.dart';

NyaNyaWebview(
  options: WebViewOptions(
    engine: WebViewEngine.gecko,
    initialUrl: 'https://example.com',
    serverPort: 13218,
    newTabBehavior: NewTabBehavior.delegate,
  ),
  onCommunicationCreated: (communication) {
    // 通信接口就绪
  },
  onOpenUrl: (url, target) {
    // 处理新开页面
  },
)
```

### 带标签页使用

```dart
TabManagerWidget(
  initialUrl: 'https://example.com',
  optionsBuilder: (url) => WebViewOptions(
    engine: WebViewEngine.gecko,
    initialUrl: url,
    serverPort: 13218,
    newTabBehavior: NewTabBehavior.delegate,
  ),
  maxTabs: 10,
  language: 'zh-CN',
)
```

## 配置选项

### WebViewOptions

| 参数                 | 类型                    | 默认值     | 说明            |
| -------------------- | ----------------------- | ---------- | --------------- |
| `engine`             | `WebViewEngine`         | `gecko`    | 渲染引擎        |
| `initialUrl`         | `String`                | 必填       | 初始 URL        |
| `serverPort`         | `int?`                  | `null`     | 本地服务器端口  |
| `enableJavascript`   | `bool`                  | `true`     | 启用 JavaScript |
| `enableGeolocation`  | `bool`                  | `false`    | 启用定位        |
| `enableMixedContent` | `bool`                  | `true`     | 允许混合内容    |
| `newTabBehavior`     | `NewTabBehavior`        | `delegate` | 新页面行为      |
| `urlRewriteRules`    | `List<UrlRewriteRule>?` | `null`     | URL 替换规则    |

### URL 规则替换

```dart
WebViewOptions(
  initialUrl: 'https://example.com',
  urlRewriteRules: [
    UrlRewriteRule(
      pattern: RegExp(r'https?://localhost:13218'),
      replacement: 'https://production.example.com',
    ),
  ],
)
```

### 新页面行为

- `replace` - 在当前 WebView 中加载
- `delegate` - 委托给 Flutter 层处理（推荐）

## 通信接口

```dart
onCommunicationCreated: (IWebViewCommunication communication) {
  // 发送消息到 WebView
  await communication.postMessage('Hello from Flutter');

  // 注册消息监听
  communication.setMessageHandler((message) {
    print('Received: $message');
  });
}
```

## 国际化

TabPage 内置 i18n 支持：

| Key         | zh-CN     | zh-TW     | en-US       |
| ----------- | --------- | --------- | ----------- |
| share       | 分享      | 分享      | Share       |
| url_copied  | 已复制URL | 已複製URL | URL copied  |
| copy_failed | 复制失败  | 複製失敗  | Copy failed |
| loading     | 加载中... | 載入中... | Loading...  |

传入 `language` 参数自动切换：

- `zh-CN` - 简体中文
- `zh-TW` - 繁体中文
- `en-US` - 英文（默认）

## API 参考

### 通信接口方法

| 方法                         | 返回值         | 说明         |
| ---------------------------- | -------------- | ------------ |
| `loadUrl(url)`               | `Future<void>` | 加载 URL     |
| `reload()`                   | `Future<void>` | 刷新页面     |
| `goBack()`                   | `Future<void>` | 后退         |
| `goForward()`                | `Future<void>` | 前进         |
| `canGoBack()`                | `Future<bool>` | 是否可后退   |
| `canGoForward()`             | `Future<bool>` | 是否可前进   |
| `evaluateJavascript(script)` | `Future<void>` | 执行 JS      |
| `postMessage(message)`       | `Future<void>` | 发送消息     |
| `checkReady()`               | `Future<bool>` | 检查就绪状态 |

## 目录结构

```
nyanya_webview/
├── lib/
│   ├── nyanya_webview.dart          # 导出入口
│   └── src/
│       ├── webview_options.dart     # 配置选项
│       ├── webview_controller.dart  # 控制器
│       ├── webview_communication_interface.dart  # 通信接口
│       └── tab_manager/             # 标签页管理
│           ├── tab_manager.dart
│           ├── tab_page.dart
│           └── tab_manager_widget.dart
└── android/                         # Android 原生实现
```

## 相关文档

- [开发文档](./DEVELOPMENT.md)
- [tab_manager 开发文档](./lib/src/tab_manager/DEVELOPMENT.md)

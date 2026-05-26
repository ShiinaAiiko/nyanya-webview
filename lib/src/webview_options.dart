enum WebViewEngine {
  gecko,
  system,
}

enum NewTabBehavior {
  replace,
  delegate,
}

typedef OpenUrlHandler = void Function(String url, String? target);

class UrlRewriteRule {
  final RegExp pattern;
  final String replacement;

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

  const WebViewOptions({
    this.engine = WebViewEngine.gecko,
    required this.initialUrl,
    this.enableJavascript = true,
    this.enableGeolocation = false,
    this.enableMixedContent = true,
    this.serverPort,
    this.headers,
    this.newTabBehavior = NewTabBehavior.delegate,
    this.urlRewriteRules,
  });

  WebViewOptions copyWith({
    WebViewEngine? engine,
    String? initialUrl,
    bool? enableJavascript,
    bool? enableGeolocation,
    bool? enableMixedContent,
    int? serverPort,
    Map<String, String>? headers,
    NewTabBehavior? newTabBehavior,
    List<UrlRewriteRule>? urlRewriteRules,
  }) {
    return WebViewOptions(
      engine: engine ?? this.engine,
      initialUrl: initialUrl ?? this.initialUrl,
      enableJavascript: enableJavascript ?? this.enableJavascript,
      enableGeolocation: enableGeolocation ?? this.enableGeolocation,
      enableMixedContent: enableMixedContent ?? this.enableMixedContent,
      serverPort: serverPort ?? this.serverPort,
      headers: headers ?? this.headers,
      newTabBehavior: newTabBehavior ?? this.newTabBehavior,
      urlRewriteRules: urlRewriteRules ?? this.urlRewriteRules,
    );
  }

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

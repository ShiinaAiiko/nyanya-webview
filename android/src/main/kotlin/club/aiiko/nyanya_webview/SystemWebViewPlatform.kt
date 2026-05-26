package club.aiiko.nyanya_webview

import android.content.Context
import android.content.Intent
import android.net.Uri
import android.os.Build
import android.util.Log
import android.webkit.*
import android.widget.FrameLayout
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugin.platform.PlatformView

class SystemWebViewPlatform(
    private val context: Context,
    messenger: BinaryMessenger,
    id: Int,
    creationParams: Map<String, Any>?
) : PlatformView, MethodChannel.MethodCallHandler {

    private val TAG = "SystemWebViewPlatform"
    private val webView: WebView
    private lateinit var methodChannel: MethodChannel
    private val container: FrameLayout
    private val serverPort: Int = creationParams?.get("serverPort") as? Int ?: 13218

    init {
        Log.d("NyaNyaWebViewLog", "SystemWebViewPlatform.init STARTED, id=$id")
        Log.d(TAG, "Creating SystemWebViewPlatform with serverPort: $serverPort")

        container = FrameLayout(context)

        // 先创建 methodChannel
        try {
            val channelName = "club.aiiko.system_view_$id"
            Log.d("NyaNyaWebViewLog", "SystemWebViewPlatform: Creating MethodChannel with name: $channelName")
            methodChannel = MethodChannel(messenger, channelName)
            methodChannel.setMethodCallHandler(this)
            Log.d("NyaNyaWebViewLog", "SystemWebViewPlatform: MethodCallHandler successfully set!")
        } catch (e: Exception) {
            Log.e("NyaNyaWebViewLog", "SystemWebViewPlatform: ERROR creating MethodChannel!", e)
            throw e
        }

        webView = WebView(context).apply {
            layoutParams = FrameLayout.LayoutParams(
                FrameLayout.LayoutParams.MATCH_PARENT,
                FrameLayout.LayoutParams.MATCH_PARENT
            )
            settings.javaScriptEnabled = creationParams?.get("enableJavascript") as? Boolean ?: true
            settings.domStorageEnabled = true
            settings.allowFileAccess = true
            settings.allowContentAccess = true
            settings.mediaPlaybackRequiresUserGesture = false

            // 允许混合内容
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.LOLLIPOP) {
                settings.mixedContentMode = WebSettings.MIXED_CONTENT_ALWAYS_ALLOW
            }

            // 设置 WebViewClient
            webViewClient = object : WebViewClient() {
                override fun onPageFinished(view: WebView?, url: String?) {
                    super.onPageFinished(view, url)
                    methodChannel.invokeMethod("onPageStop", null)
                    // 页面加载完成后注入 JavaScript
                    injectFlutterBridge()
                }

                override fun onPageStarted(view: WebView?, url: String?, favicon: android.graphics.Bitmap?) {
                    super.onPageStarted(view, url, favicon)
                    methodChannel.invokeMethod("onPageStart", null)
                }
            }

            // 设置 WebChromeClient
            webChromeClient = object : WebChromeClient() {
                override fun onJsPrompt(
                    view: WebView?,
                    url: String?,
                    message: String?,
                    defaultValue: String?,
                    result: JsPromptResult?
                ): Boolean {
                    if (message != null && result != null) {
                        methodChannel.invokeMethod("onWebMessage", message)
                        result.confirm("")
                        return true
                    }
                    return super.onJsPrompt(view, url, message, defaultValue, result)
                }

                override fun onCreateWindow(view: WebView?, isDialog: Boolean, isUserGesture: Boolean, resultMsg: android.os.Message?): Boolean {
                    Log.d("NyaNyaWebViewLog", "SystemWebViewPlatform: onCreateWindow called, isUserGesture=$isUserGesture")
                    
                    // 创建临时 WebView 来捕获 URL
                    val newWebView = WebView(context)
                    newWebView.settings.javaScriptEnabled = true
                    
                    // 设置 WebViewClient 来捕获 URL
                    newWebView.webViewClient = object : WebViewClient() {
                        override fun onPageStarted(view: WebView?, url: String?, favicon: android.graphics.Bitmap?) {
                            super.onPageStarted(view, url, favicon)
                            Log.d("NyaNyaWebViewLog", "SystemWebViewPlatform: onCreateWindow intercepted URL: $url")
                            if (url != null && url != "about:blank") {
                                try {
                                    val params = mapOf("url" to url, "target" to "_blank")
                                    Log.d("NyaNyaWebViewLog", "SystemWebViewPlatform: Preparing to invoke onOpenUrl to Flutter, params=$params")
                                    
                                    android.os.Handler(android.os.Looper.getMainLooper()).post {
                                        try {
                                            Log.d("NyaNyaWebViewLog", "SystemWebViewPlatform: NOW invoking methodChannel.invokeMethod('onOpenUrl', $params)")
                                            methodChannel.invokeMethod("onOpenUrl", params)
                                            Log.d("NyaNyaWebViewLog", "SystemWebViewPlatform: invokeMethod('onOpenUrl') completed successfully!")
                                        } catch (e: Exception) {
                                            Log.e("NyaNyaWebViewLog", "SystemWebViewPlatform: ERROR in invokeMethod('onOpenUrl')!", e)
                                            e.printStackTrace()
                                        }
                                    }
                                } catch (e: Exception) {
                                    Log.e("NyaNyaWebViewLog", "SystemWebViewPlatform: Error preparing to invoke onOpenUrl", e)
                                    e.printStackTrace()
                                }
                            }
                            // 取消新窗口创建
                            resultMsg?.let {
                                val transport = it.obj as WebView.WebViewTransport
                                transport.webView = null
                                it.sendToTarget()
                            }
                            newWebView.stopLoading()
                        }
                    }
                    
                    // 将新 WebView 设置到 transport
                    resultMsg?.let {
                        val transport = it.obj as WebView.WebViewTransport
                        transport.webView = newWebView
                        it.sendToTarget()
                    }
                    
                    return true
                }
            }

            // 添加 JavaScript 接口
            addJavascriptInterface(WebAppInterface(methodChannel), "NyanyaBridge")
        }

        container.addView(webView)

        // 加载初始 URL
        val initialUrl = creationParams?.get("url") as? String ?: "about:blank"
        webView.loadUrl(initialUrl)

        Log.d(TAG, "SystemWebViewPlatform created successfully")
    }

    /**
     * 注入 Flutter Bridge JavaScript 代码
     * 与 GeckoView 实现保持一致
     */
    private fun injectFlutterBridge() {
        val bridgeScript = """
            (function() {
                window.isFlutterApp = true;
                window.flutterServerPort = $serverPort;
                window.flutterServerHost = 'http://127.0.0.1:$serverPort';

                // 如果没有 ReactNativeWebView，设置它
                if (!window.ReactNativeWebView) {
                    window.ReactNativeWebView = {
                        postMessage: function(message) {
                            var xhr = new XMLHttpRequest();
                            xhr.open('GET', 'http://127.0.0.1:$serverPort/__flutter_bridge__?message=' + encodeURIComponent(message), true);
                            xhr.send();
                        }
                    };
                }

                // URL 变化检测
                (function() {
                    var lastUrl = window.location.href;
                    var lastTitle = document.title;
                    var lastSentUrl = '';
                    var sendCount = 0;
                    var maxSendCount = 3;
                    var checkInterval = null;

                    function notifyChange() {
                        var currentUrl = window.location.href;
                        var currentTitle = document.title;

                        if (currentUrl !== lastUrl || currentTitle !== lastTitle) {
                            lastUrl = currentUrl;
                            lastTitle = currentTitle;

                            if (currentUrl !== lastSentUrl) {
                                sendCount = 0;
                                lastSentUrl = currentUrl;
                            }

                            if (sendCount < maxSendCount) {
                                try {
                                    window.ReactNativeWebView.postMessage(JSON.stringify({type: 'url_change', url: currentUrl, title: currentTitle}));
                                    sendCount++;
                                } catch(e) {}
                            }
                        }
                    }

                    checkInterval = setInterval(notifyChange, 500);

                    window.addEventListener('beforeunload', function() {
                        if (checkInterval) clearInterval(checkInterval);
                    });
                })();
            })();
        """.trimIndent()

        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.KITKAT) {
            webView.evaluateJavascript(bridgeScript, null)
        }
    }

    override fun getView() = container

    override fun dispose() {
        Log.d(TAG, "Disposing SystemWebViewPlatform")
        webView.stopLoading()
        webView.removeAllViews()
        webView.destroy()
        methodChannel.setMethodCallHandler(null)
    }

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "loadUrl" -> {
                val url = call.argument<String>("url")
                Log.d(TAG, "loadUrl called with: $url")
                webView.loadUrl(url ?: "")
                result.success(null)
            }
            "reload" -> {
                Log.d(TAG, "reload called")
                webView.reload()
                result.success(null)
            }
            "goBack" -> {
                Log.d(TAG, "goBack called")
                if (webView.canGoBack()) {
                    webView.goBack()
                }
                result.success(null)
            }
            "goForward" -> {
                Log.d(TAG, "goForward called")
                if (webView.canGoForward()) {
                    webView.goForward()
                }
                result.success(null)
            }
            "canGoBack" -> {
                result.success(webView.canGoBack())
            }
            "canGoForward" -> {
                result.success(webView.canGoForward())
            }
            "evaluateJavascript" -> {
                val script = call.argument<String>("script")
                Log.d(TAG, "evaluateJavascript called")
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.KITKAT) {
                    webView.evaluateJavascript(script ?: "") { value ->
                        result.success(value)
                    }
                } else {
                    webView.loadUrl("javascript:$script")
                    result.success(null)
                }
            }
            "postMessage" -> {
                val message = call.argument<String>("message")
                Log.d(TAG, "postMessage called: $message")

                if (message != null) {
                    val wrappedMessage = "if (window.onFlutterMessage) { window.onFlutterMessage($message); }"
                    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.KITKAT) {
                        webView.evaluateJavascript(wrappedMessage, null)
                    } else {
                        webView.loadUrl("javascript:$wrappedMessage")
                    }
                    result.success(null)
                } else {
                    result.error("INVALID_MESSAGE", "Message is null", null)
                }
            }
            "setGeolocation" -> {
                val latitude = call.argument<Double>("latitude")
                val longitude = call.argument<Double>("longitude")
                val accuracy = call.argument<Double>("accuracy") ?: 10.0
                val altitude = call.argument<Double>("altitude")
                val heading = call.argument<Double>("heading")
                val speed = call.argument<Double>("speed")
                val timestamp = call.argument<Double>("timestamp") ?: (System.currentTimeMillis().toDouble())

                if (latitude != null && longitude != null) {
                    val positionJson = buildString {
                        append("{coords:{")
                        append("latitude:$latitude,")
                        append("longitude:$longitude,")
                        append("accuracy:$accuracy,")
                        if (altitude != null) append("altitude:$altitude,")
                        if (heading != null) append("heading:$heading,")
                        if (speed != null) append("speed:$speed,")
                        append("altitudeAccuracy:${accuracy}")
                        append("}},")
                        append("timestamp:$timestamp")
                        append("}")
                    }

                    val js = """
                        (function() {
                            if (window._geolocationSuccessCallback) {
                                window._geolocationSuccessCallback($positionJson);
                            }
                            if (window.navigator && window.navigator.geolocation && window._geolocationWatchId !== null) {
                                var mockPosition = $positionJson;
                                window.navigator.geolocation._successHandler(mockPosition);
                            }
                        })();
                    """.trimIndent()
                    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.KITKAT) {
                        webView.evaluateJavascript(js, null)
                    } else {
                        webView.loadUrl("javascript:$js")
                    }
                    result.success(null)
                } else {
                    result.error("INVALID_COORDS", "latitude or longitude is null", null)
                }
            }
            "setGeolocationError" -> {
                val code = call.argument<String>("code") ?: "POSITION_UNAVAILABLE"
                val message = call.argument<String>("message") ?: "Position unavailable"

                val js = """
                    (function() {
                        if (window._geolocationErrorCallback) {
                            window._geolocationErrorCallback({code: '$code', message: '$message'});
                        }
                        if (window.navigator && window.navigator.geolocation && window._geolocationWatchId !== null) {
                            window.navigator.geolocation._errorHandler({code: 2, message: '$message'});
                        }
                    })();
                """.trimIndent()
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.KITKAT) {
                    webView.evaluateJavascript(js, null)
                } else {
                    webView.loadUrl("javascript:$js")
                }
                result.success(null)
            }
            "openInBrowser" -> {
                val url = call.argument<String>("url")
                if (url != null) {
                    Log.d(TAG, "openInBrowser called with url: $url")
                    try {
                        val uri = Uri.parse(url)
                        val intent = Intent(Intent.ACTION_VIEW, uri)
                        intent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                        context.startActivity(intent)
                        result.success(null)
                    } catch (e: Exception) {
                        Log.e(TAG, "Error opening in browser: ${e.message}", e)
                        result.error("OPEN_BROWSER_ERROR", e.message, null)
                    }
                } else {
                    Log.e(TAG, "openInBrowser called with null url")
                    result.error("INVALID_URL", "URL is null", null)
                }
            }
            "checkWebViewReady" -> {
                Log.d(TAG, "checkWebViewReady called")
                val isReady = webView.url != null
                Log.d(TAG, "SystemWebView check: ready=$isReady")
                result.success(isReady)
            }
            "checkSessionsHealth" -> {
                Log.d(TAG, "checkSessionsHealth called")
                result.success(true)
            }
            "dispose" -> {
                dispose()
                result.success(null)
            }
            else -> result.notImplemented()
        }
    }

    /**
     * JavaScript 接口类
     */
    class WebAppInterface(private val methodChannel: MethodChannel) {
        @JavascriptInterface
        fun postMessage(message: String) {
            methodChannel.invokeMethod("onWebMessage", message)
        }
    }
}

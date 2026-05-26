package club.aiiko.nyanya_webview

import android.Manifest
import android.content.Context
import android.content.pm.PackageManager
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.util.Log
import android.view.View
import android.view.inputmethod.EditorInfo
import android.view.inputmethod.InputConnection
import androidx.core.app.ActivityCompat
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugin.platform.PlatformView
import org.mozilla.geckoview.GeckoResult
import org.mozilla.geckoview.GeckoRuntime
import org.mozilla.geckoview.GeckoRuntimeSettings
import org.mozilla.geckoview.GeckoSession
import org.mozilla.geckoview.GeckoSessionSettings
import org.mozilla.geckoview.GeckoView

data class TabSession(
    val session: GeckoSession,
    val url: String,
    val title: String = "",
    val id: Long = System.currentTimeMillis(),
    var canGoBack: Boolean = false,
    var canGoForward: Boolean = false
)

class TabManager(
    private val context: Context,
    private val methodChannel: MethodChannel,
    private val geckoView: GeckoView,
    private var serverPort: Int = 8080,
    private var sessionId: String? = null
) {
    companion object {
        private const val TAG = "TabManager"
    }

    val tabStack = mutableListOf<TabSession>()
    var currentTabIndex = -1
    var currentTabCanGoBack: Boolean = false
    var currentTabCanGoForward: Boolean = false

    val currentSession: GeckoSession?
        get() = if (currentTabIndex >= 0 && currentTabIndex < tabStack.size) {
            tabStack[currentTabIndex].session
        } else null

    val tabCount: Int
        get() = tabStack.size

    val canGoBack: Boolean
        get() = tabStack.size > 1

    val currentTab: TabSession?
        get() = if (currentTabIndex >= 0 && currentTabIndex < tabStack.size) {
            tabStack[currentTabIndex]
        } else null

    fun createNewTab(url: String): TabSession {
        Log.d("NyaNyaWebViewLog-Native", "Creating new tab for URL: $url")
        val sessionSettings = GeckoSessionSettings.Builder()
            .usePrivateMode(false)
            .build()
        val session = GeckoSession(sessionSettings)
        session.open(GeckoViewPlatform.getRuntime(context))

        val tabSession = TabSession(session, url, "")
        tabStack.add(tabSession)
        currentTabIndex = tabStack.size - 1
        session.loadUri(url)
        notifyTabStackChanged()

        return tabSession
    }

    fun addTab(session: GeckoSession, url: String): TabSession {
        Log.d("NyaNyaWebViewLog-Native", "Adding existing session as new tab: $url")
        val tabSession = TabSession(session, url, "")
        tabStack.add(tabSession)
        currentTabIndex = tabStack.size - 1
        geckoView.setSession(session)
        notifyTabStackChanged()
        return tabSession
    }

    fun closeCurrentTab(): Boolean {
        if (tabStack.size <= 1) {
            Log.d("NyaNyaWebViewLog-Native", "Cannot close last tab")
            return false
        }
        val tab = currentTab
        if (tab != null) {
            Log.d("NyaNyaWebViewLog-Native", "Closing tab: ${tab.title}")
            tab.session.close()
            tabStack.removeAt(currentTabIndex)
            currentTabIndex = tabStack.size - 1
            val prevSession = currentSession
            if (prevSession != null) {
                geckoView.setSession(prevSession)
            }
            notifyTabStackChanged()
            return true
        }
        return false
    }

    fun closeTab(tabId: Long): Boolean {
        val index = tabStack.indexOfFirst { it.id == tabId }
        if (index >= 0) {
            if (index == currentTabIndex && tabStack.size <= 1) {
                return false
            }
            Log.d("NyaNyaWebViewLog-Native", "Closing tab by id: $tabId")
            tabStack[index].session.close()
            tabStack.removeAt(index)
            if (index <= currentTabIndex) {
                currentTabIndex = (currentTabIndex - 1).coerceAtLeast(0)
            }
            val currentSession = currentSession
            if (currentSession != null) {
                geckoView.setSession(currentSession)
            }
            notifyTabStackChanged()
            return true
        }
        return false
    }

    fun goBackToPreviousTab(): Boolean {
        if (canGoBack) {
            Log.d("NyaNyaWebViewLog-Native", "Going back to previous tab")
            closeCurrentTab()
            return true
        }
        return false
    }

    fun getTabsInfo(): List<Map<String, Any>> {
        return tabStack.mapIndexed { index, tab ->
            mapOf(
                "id" to tab.id,
                "url" to tab.url,
                "title" to tab.title,
                "isCurrent" to (index == currentTabIndex)
            )
        }
    }

    private fun updateTab(session: GeckoSession, url: String? = null, title: String? = null) {
        val index = tabStack.indexOfFirst { it.session == session }
        Log.d("NyaNyaWebViewLog-Native", "updateTab called: session=$session, url=$url, title=$title, found index=$index, tabStack size=${tabStack.size}")
        if (index >= 0) {
            val oldTab = tabStack[index]
            tabStack[index] = oldTab.copy(
                url = url ?: oldTab.url,
                title = title ?: oldTab.title
            )
            Log.d("NyaNyaWebViewLog-Native", "Tab updated: new url=${tabStack[index].url}, new title=${tabStack[index].title}")
        } else {
            Log.w("NyaNyaWebViewLog-Native", "Tab not found in tabStack for session: $session")
        }
    }

    fun notifyTabChanged() {
        try {
            val tab = currentTab
            if (tab != null) {
                methodChannel.invokeMethod(
                    "onTabChanged",
                    mapOf(
                        "id" to tab.id,
                        "url" to tab.url,
                        "title" to tab.title
                    )
                )
            }
        } catch (e: Exception) {
            Log.e("NyaNyaWebViewLog-Native", "Error notifying tab changed: ${e.message}")
        }
    }

    fun notifyTabStackChanged() {
        try {
            val tabsInfo = tabStack.mapIndexed { index, tab ->
                mapOf(
                    "id" to tab.id,
                    "url" to tab.url,
                    "title" to tab.title,
                    "isCurrent" to (index == currentTabIndex),
                    "canGoBack" to tab.canGoBack,
                    "canGoForward" to tab.canGoForward
                )
            }
            Log.d("NyaNyaWebViewLog-Native", "notifyTabStackChanged: canGoBack=$currentTabCanGoBack, canGoForward=$currentTabCanGoForward, tabs=${tabsInfo.size}")
            methodChannel.invokeMethod(
                "onTabStackChanged",
                mapOf(
                    "tabs" to tabsInfo,
                    "canGoBack" to currentTabCanGoBack,
                    "canGoForward" to currentTabCanGoForward
                )
            )
        } catch (e: Exception) {
            Log.e("NyaNyaWebViewLog-Native", "Error notifying tab stack changed: ${e.message}")
        }
    }

    fun requestExitApp(): Boolean {
        try {
            methodChannel.invokeMethod("onRequestExitApp", null)
            return true
        } catch (e: Exception) {
            Log.e("NyaNyaWebViewLog-Native", "Error invoking onRequestExitApp: ${e.message}")
            return false
        }
    }

    fun setupSession(session: GeckoSession, port: Int) {
        this.serverPort = port
        
        session.progressDelegate = object : GeckoSession.ProgressDelegate {
            override fun onPageStart(s: GeckoSession, url: String) {
                Log.d("NyaNyaWebViewLog-Native", "onPageStart for tab: $url")
                try {
                    methodChannel.invokeMethod("onPageStart", mapOf("url" to url))
                } catch (e: Exception) {
                    Log.e("NyaNyaWebViewLog-Native", "Error invoking onPageStart: ${e.message}")
                }
            }

            override fun onPageStop(s: GeckoSession, success: Boolean) {
                Log.d("NyaNyaWebViewLog-Native", "onPageStop for tab: $success")
                try {
                    methodChannel.invokeMethod("onPageStop", mapOf("success" to success))
                    if (success) {
                        val index = tabStack.indexOfFirst { it.session == s }
                        if (index >= 0) {
                            val currentUrl = tabStack[index].url
                            Log.d("NyaNyaWebViewLog-Native", "onPageStop: currentUrl=$currentUrl")
                            methodChannel.invokeMethod("onLocationChange", mapOf("url" to currentUrl))
                        }
                    }
                } catch (e: Exception) {
                    Log.e("NyaNyaWebViewLog-Native", "Error invoking onPageStop: ${e.message}")
                }
                if (success) {
                    val handler = Handler(Looper.getMainLooper())
                    handler.postDelayed({
                        injectGeolocationMock(s)
                        injectJSBridge(s)
                        geckoView.requestFocus()
                    }, 300)
                }
            }
        }

        session.contentDelegate = object : GeckoSession.ContentDelegate {
            override fun onTitleChange(s: GeckoSession, title: String?) {
                Log.d("NyaNyaWebViewLog-Native", "Title changed for tab: $title")
                updateTab(s, title = title ?: "")
                try {
                    methodChannel.invokeMethod(
                        "onTitleChange",
                        mapOf("title" to (title ?: ""))
                    )
                } catch (e: Exception) {
                    Log.e("NyaNyaWebViewLog-Native", "Error invoking onTitleChange: ${e.message}")
                }
            }
        }

        session.permissionDelegate = object : GeckoSession.PermissionDelegate {
            override fun onContentPermissionRequest(
                session: GeckoSession,
                permission: GeckoSession.PermissionDelegate.ContentPermission
            ): GeckoResult<Int> {
                if (permission.permission == GeckoSession.PermissionDelegate.PERMISSION_GEOLOCATION) {
                    if (hasLocationPermission()) {
                        return GeckoResult.fromValue(
                            GeckoSession.PermissionDelegate.ContentPermission.VALUE_ALLOW
                        )
                    } else {
                        return GeckoResult.fromValue(
                            GeckoSession.PermissionDelegate.ContentPermission.VALUE_DENY
                        )
                    }
                }
                return GeckoResult.fromValue(
                    GeckoSession.PermissionDelegate.ContentPermission.VALUE_ALLOW
                )
            }

            override fun onAndroidPermissionsRequest(
                session: GeckoSession,
                permissions: Array<out String>?,
                callback: GeckoSession.PermissionDelegate.Callback
            ) {
                val hasAllPermissions = permissions?.all { perm ->
                    ActivityCompat.checkSelfPermission(context, perm) == PackageManager.PERMISSION_GRANTED
                } ?: true

                if (hasAllPermissions) {
                    callback.grant()
                } else {
                    callback.reject()
                }
            }
        }

        session.promptDelegate = object : GeckoSession.PromptDelegate {
            override fun onAlertPrompt(session: GeckoSession, prompt: GeckoSession.PromptDelegate.AlertPrompt): GeckoResult<GeckoSession.PromptDelegate.PromptResponse>? {
                return GeckoResult.fromValue(prompt.dismiss())
            }

            override fun onTextPrompt(session: GeckoSession, prompt: GeckoSession.PromptDelegate.TextPrompt): GeckoResult<GeckoSession.PromptDelegate.PromptResponse>? {
                val msg = prompt.message ?: ""
                if (msg.startsWith("__flutter_bridge__:")) {
                    val jsonMessage = msg.removePrefix("__flutter_bridge__:")
                    Log.d("NyaNyaWebViewLog-Native", "JS Bridge message received: $jsonMessage")
                    try {
                        methodChannel.invokeMethod("onWebMessage", jsonMessage)
                    } catch (e: Exception) {
                        Log.e("NyaNyaWebViewLog-Native", "Error invoking onWebMessage: ${e.message}")
                    }
                    return GeckoResult.fromValue(prompt.confirm(""))
                }
                return null
            }
        }

        Log.d("NyaNyaWebViewLog-Native", "setupSession called for session: $session")
        session.navigationDelegate = object : GeckoSession.NavigationDelegate {
            override fun onLocationChange(
                session: GeckoSession, 
                url: String?, 
                permissions: List<GeckoSession.PermissionDelegate.ContentPermission>, 
                isDraft: Boolean
            ) {
                Log.d("NyaNyaWebViewLog-Native", "URL 改变 (新版 API): $url")
                
                // 你的业务逻辑保持不变
                try {
                    methodChannel.invokeMethod(
                        "onLocationChange",
                        mapOf("url" to (url ?: ""))
                    )
                } catch (e: Exception) {
                    Log.e("NyaNyaWebViewLog-Native", "Error: ${e.message}")
                }
            }
    
            override fun onNewSession(s: GeckoSession, uri: String): GeckoResult<GeckoSession>? {
                Log.d("NyaNyaWebViewLog-Native", "TabManager: onNewSession called, uri=$uri")
                Log.d("NyaNyaWebViewLog-Native", "TabManager: methodChannel hash = ${System.identityHashCode(methodChannel)}")
                
                try {
                    val params = mapOf("url" to uri, "target" to "_blank")
                    Log.d("NyaNyaWebViewLog-Native", "TabManager: Preparing to invoke onOpenUrl to Flutter, params=$params")
                    
                    // 确保在主线程上调用
                    Handler(Looper.getMainLooper()).post {
                        try {
                            Log.d("NyaNyaWebViewLog-Native", "TabManager: NOW invoking methodChannel.invokeMethod('onOpenUrl', $params)")
                            Log.d("NyaNyaWebViewLog-Native", "TabManager: methodChannel reference = $methodChannel")
                            Log.d("NyaNyaWebViewLog-Native", "TabManager: methodChannel identity hash = ${System.identityHashCode(methodChannel)}")
                            methodChannel.invokeMethod("onOpenUrl", params, object : MethodChannel.Result {
                                override fun success(result: Any?) {
                                    Log.d("NyaNyaWebViewLog-Native", "TabManager: onOpenUrl success! result = $result")
                                }
                                override fun error(errorCode: String, errorMessage: String?, errorDetails: Any?) {
                                    Log.e("NyaNyaWebViewLog-Native", "TabManager: onOpenUrl ERROR! code=$errorCode, msg=$errorMessage, details=$errorDetails")
                                }
                                override fun notImplemented() {
                                    Log.e("NyaNyaWebViewLog-Native", "TabManager: onOpenUrl NOT IMPLEMENTED!")
                                }
                            })
                            Log.d("NyaNyaWebViewLog-Native", "TabManager: invokeMethod('onOpenUrl') returned normally")
                        } catch (e: Exception) {
                            Log.e("NyaNyaWebViewLog-Native", "TabManager: ERROR in invokeMethod('onOpenUrl')!", e)
                            e.printStackTrace()
                        }
                    }
                } catch (e: Exception) {
                    Log.e("NyaNyaWebViewLog-Native", "TabManager: Error preparing to invoke onOpenUrl", e)
                    e.printStackTrace()
                }
                return null
            }

            override fun onCanGoBack(session: GeckoSession, canGoBack: Boolean) {
                Log.d("NyaNyaWebViewLog-Native", "onCanGoBack changed: $canGoBack for session")
                currentTabCanGoBack = canGoBack
                val index = tabStack.indexOfFirst { it.session == session }
                if (index >= 0) {
                    val oldTab = tabStack[index]
                    tabStack[index] = oldTab.copy(canGoBack = canGoBack)
                }
                Log.d("NyaNyaWebViewLog-Native", "currentTabCanGoBack updated to: $currentTabCanGoBack")
                notifyTabStackChanged()
            }

            override fun onCanGoForward(session: GeckoSession, canGoForward: Boolean) {
                Log.d("NyaNyaWebViewLog-Native", "onCanGoForward changed: $canGoForward for session")
                currentTabCanGoForward = canGoForward
                val index = tabStack.indexOfFirst { it.session == session }
                if (index >= 0) {
                    val oldTab = tabStack[index]
                    tabStack[index] = oldTab.copy(canGoForward = canGoForward)
                }
                notifyTabStackChanged()
            }
        }
        Log.d("NyaNyaWebViewLog-Native", "NavigationDelegate set for session: $session")
    }

    private fun hasLocationPermission(): Boolean {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
            val hasFine = ActivityCompat.checkSelfPermission(
                context,
                Manifest.permission.ACCESS_FINE_LOCATION
            ) == PackageManager.PERMISSION_GRANTED
            val hasCoarse = ActivityCompat.checkSelfPermission(
                context,
                Manifest.permission.ACCESS_COARSE_LOCATION
            ) == PackageManager.PERMISSION_GRANTED
            return hasFine || hasCoarse
        }
        return true
    }

    private fun injectGeolocationMock(session: GeckoSession) {
        val mockScript = """
            (function() {
                window._geolocationWatchId = null;
                window._geolocationSuccessCallback = null;
                window._geolocationErrorCallback = null;

                var Geolocation = function() {};

                Geolocation.prototype.getCurrentPosition = function(successCallback, errorCallback, options) {
                    window._geolocationSuccessCallback = successCallback;
                    window._geolocationErrorCallback = errorCallback;
                    if (window._geolocationSuccessCallback) {
                        window.postMessage({type: 'GEOLOCATION_REQUEST', action: 'getCurrentPosition'}, '*');
                    }
                };

                Geolocation.prototype.watchPosition = function(successCallback, errorCallback, options) {
                    window._geolocationSuccessCallback = successCallback;
                    window._geolocationErrorCallback = errorCallback;
                    window._geolocationWatchId = window._geolocationWatchId || 1;
                    window.postMessage({type: 'GEOLOCATION_REQUEST', action: 'watchPosition'}, '*');
                    return window._geolocationWatchId;
                };

                Geolocation.prototype.clearWatch = function(watchId) {
                    if (watchId === window._geolocationWatchId) {
                        window._geolocationWatchId = null;
                    }
                };

                if (!window.navigator.geolocation) {
                    Object.defineProperty(window.navigator, 'geolocation', {
                        value: new Geolocation(),
                        writable: false,
                        configurable: true
                    });
                }
            })();
        """.trimIndent()
        session.loadUri("javascript:$mockScript")
    }

    private fun injectJSBridge(session: GeckoSession) {
        Log.d("NyaNyaWebViewLog-Native", "Injecting JS Bridge with serverPort: $serverPort, sessionId: $sessionId")
        val sessionIdPart = if (sessionId != null) "window.nyanyaSessionId = '$sessionId';" else ""
        val bridgeScript = """
            window.isFlutterApp = true;
            window.flutterServerPort = $serverPort;
            window.flutterServerHost = 'http://127.0.0.1:$serverPort';
            $sessionIdPart
            if (!window.nyanyaWebView) {
                window.nyanyaWebView = {
                    postMessage: function(message) {
                        window.prompt('__flutter_bridge__:' + message);
                    }
                };
               window.nyanyaWebView.postMessage(JSON.stringify({
                             type: 'test',
                             payload: {url: 'test', title: 'test'}
                         }));
            };
            (function() {})();
        """.trimIndent()
        session.loadUri("javascript:$bridgeScript")
    }
}

class GeckoViewPlatform(
    private val context: Context,
    messenger: BinaryMessenger,
    id: Int,
    creationParams: Map<String, Any>?
) : PlatformView, MethodChannel.MethodCallHandler {

    private val TAG = "GeckoViewPlatform"
    private val geckoView: GeckoView
    private val methodChannel: MethodChannel
    private val handler = Handler(Looper.getMainLooper())
    private val serverPort: Int
    private lateinit var tabManager: TabManager

    companion object {
        private var geckoRuntime: GeckoRuntime? = null
        private var isRuntimeShutdown: Boolean = false

        fun getRuntime(context: Context): GeckoRuntime {
            if (geckoRuntime != null && !isRuntimeShutdown) {
                return geckoRuntime!!
            }
            synchronized(this) {
                if (geckoRuntime != null && !isRuntimeShutdown) {
                    return geckoRuntime!!
                }
                try {
                    isRuntimeShutdown = false
                    val settings = GeckoRuntimeSettings.Builder()
                        .javaScriptEnabled(true)
                        .remoteDebuggingEnabled(true)
                        .configFilePath(null)
                        .build()
                    geckoRuntime = GeckoRuntime.create(context.applicationContext, settings)
                    Log.d("NyaNyaWebViewLog-Native", "GeckoRuntime created successfully")
                } catch (e: Exception) {
                    if (e.message?.contains("Only one GeckoRuntime instance is allowed") == true) {
                        Log.w("NyaNyaWebViewLog-Native", "GeckoRuntime already exists, reusing existing instance")
                        isRuntimeShutdown = false
                        return geckoRuntime!!
                    }
                    Log.e("NyaNyaWebViewLog-Native", "Failed to create GeckoRuntime: ${e.message}")
                    throw e
                }
            }
            return geckoRuntime!!
        }

        fun shutdownRuntime() {
            synchronized(this) {
                try {
                    geckoRuntime?.shutdown()
                } catch (e: Exception) {
                    Log.w("NyaNyaWebViewLog-Native", "Error shutting down GeckoRuntime: ${e.message}")
                }
                geckoRuntime = null
                isRuntimeShutdown = true
                Log.d("NyaNyaWebViewLog-Native", "GeckoRuntime shutdown and cleaned up")
            }
        }
    }

    init {
        Log.d("NyaNyaWebViewLog-Native", "GeckoViewPlatform.init STARTED, id=$id")
        
        try {
            val channelName = "club.aiiko.gecko_view_$id"
            Log.d("NyaNyaWebViewLog-Native", "GeckoViewPlatform: Creating MethodChannel with name: $channelName, id=$id")
            methodChannel = MethodChannel(messenger, channelName)
            methodChannel.setMethodCallHandler(this)
            Log.d("NyaNyaWebViewLog-Native", "GeckoViewPlatform: MethodCallHandler successfully set!, channel hash=${System.identityHashCode(methodChannel)}")
        } catch (e: Exception) {
            Log.e("NyaNyaWebViewLog-Native", "GeckoViewPlatform: ERROR creating MethodChannel!", e)
            throw e
        }

        val isDarkMode = creationParams?.get("isDarkMode") as? Boolean ?: true
        val bgColor = if (isDarkMode) {
            android.graphics.Color.BLACK
        } else {
            android.graphics.Color.WHITE
        }

        serverPort = creationParams?.get("serverPort") as? Int ?: 8080
        Log.d("NyaNyaWebViewLog-Native", "GeckoViewPlatform: serverPort=$serverPort")
        
        val sessionId = creationParams?.get("sessionId") as? String
        Log.d("NyaNyaWebViewLog-Native", "GeckoViewPlatform: sessionId=$sessionId")

        try {
            geckoView = GeckoViewWrapper(context).apply {
                setBackgroundColor(bgColor)

                setOnTouchListener { v, event ->
                    if (event.action == android.view.MotionEvent.ACTION_UP) {
                        v.postDelayed({
                            if (!v.hasFocus()) {
                                v.requestFocus()
                            }
                        }, 100)
                    }
                    false
                }
            }
            Log.d("NyaNyaWebViewLog-Native", "GeckoViewPlatform: GeckoViewWrapper created successfully")
        } catch (e: Exception) {
            Log.e("NyaNyaWebViewLog-Native", "GeckoViewPlatform: ERROR creating GeckoViewWrapper!", e)
            throw e
        }

        try {
            tabManager = TabManager(context, methodChannel, geckoView, serverPort, sessionId)
            Log.d("NyaNyaWebViewLog-Native", "GeckoViewPlatform: TabManager created successfully")
        } catch (e: Exception) {
            Log.e("NyaNyaWebViewLog-Native", "GeckoViewPlatform: ERROR creating TabManager!", e)
            throw e
        }

        val initialUrl = creationParams?.get("url") as? String ?: "http://localhost:8080/"
        Log.d("NyaNyaWebViewLog-Native", "GeckoViewPlatform: Initial URL to load: $initialUrl")
        
        try {
            val sessionSettings = GeckoSessionSettings.Builder()
                .usePrivateMode(false)
                .build()
            val session = GeckoSession(sessionSettings)
            session.open(getRuntime(context))
            tabManager.setupSession(session, serverPort)
            val tabSession = TabSession(session, initialUrl, "")
            tabManager.tabStack.add(tabSession)
            tabManager.currentTabIndex = 0
            geckoView.setSession(session)
            session.loadUri(initialUrl)
            tabManager.notifyTabStackChanged()
            Log.d("NyaNyaWebViewLog-Native", "GeckoViewPlatform: Initial session created and URL loaded!")
        } catch (e: Exception) {
            Log.e("NyaNyaWebViewLog-Native", "GeckoViewPlatform: ERROR creating initial session!", e)
            throw e
        }

        geckoView.setOnKeyListener { v, keyCode, event ->
            if (keyCode == android.view.KeyEvent.KEYCODE_BACK && event.action == android.view.KeyEvent.ACTION_UP) {
                Log.d("NyaNyaWebViewLog-Native", "Back button pressed")
                val currentTab = tabManager.currentTab
                val currentSession = tabManager.currentSession
                val canGoBack = tabManager.currentTabCanGoBack

                if (currentTab != null && currentSession != null) {
                    if (canGoBack) {
                        Log.d("NyaNyaWebViewLog-Native", "Going back in page history")
                        currentSession.goBack()
                    } else if (tabManager.tabCount > 1) {
                        Log.d("NyaNyaWebViewLog-Native", "No history, closing current tab")
                        tabManager.closeCurrentTab()
                    } else {
                        Log.d("NyaNyaWebViewLog-Native", "No history and only one tab, requesting exit")
                        tabManager.requestExitApp()
                    }
                }
                true
            } else {
                false
            }
        }
        
        Log.d("NyaNyaWebViewLog-Native", "GeckoViewPlatform.init COMPLETED successfully!")
    }

    override fun getView(): View {
        return geckoView
    }

    override fun dispose() {
        val currentSession = tabManager.currentSession
        if (currentSession != null) {
            currentSession.close()
        }
        methodChannel.setMethodCallHandler(null)
    }

    private var lastGeolocationCallback: String? = null

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        Log.d("NyaNyaWebViewLog-Native", "GeckoViewPlatform: onMethodCall called, method=${call.method}")
        when (call.method) {
            "testCommunication" -> {
                Log.d("NyaNyaWebViewLog-Native", "GeckoViewPlatform: testCommunication received!")
                // 回发消息给 Flutter
                try {
                    Log.d("NyaNyaWebViewLog-Native", "GeckoViewPlatform: Sending testNativeToFlutter to Flutter now...")
                    Log.d("NyaNyaWebViewLog-Native", "GeckoViewPlatform: methodChannel hash = ${System.identityHashCode(methodChannel)}")
                    methodChannel.invokeMethod("testNativeToFlutter", mapOf("message" to "Hello from native Gecko!"), object : MethodChannel.Result {
                        override fun success(result: Any?) {
                            Log.d("NyaNyaWebViewLog-Native", "GeckoViewPlatform: testNativeToFlutter success! result = $result")
                        }
                        override fun error(errorCode: String, errorMessage: String?, errorDetails: Any?) {
                            Log.e("NyaNyaWebViewLog-Native", "GeckoViewPlatform: testNativeToFlutter ERROR! code=$errorCode, msg=$errorMessage, details=$errorDetails")
                        }
                        override fun notImplemented() {
                            Log.e("NyaNyaWebViewLog-Native", "GeckoViewPlatform: testNativeToFlutter NOT IMPLEMENTED!")
                        }
                    })
                    Log.d("NyaNyaWebViewLog-Native", "GeckoViewPlatform: invokeMethod testNativeToFlutter returned normally")
                } catch (e: Exception) {
                    Log.e("NyaNyaWebViewLog-Native", "GeckoViewPlatform: Error sending testNativeToFlutter", e)
                    e.printStackTrace()
                }
                result.success(mapOf("status" to "ok", "message" to "Hello from native Gecko!"))
            }
            "loadUrl" -> {
                val url = call.argument<String>("url")
                if (url != null) {
                    val currentSession = tabManager.currentSession
                    if (currentSession != null) {
                        currentSession.loadUri(url)
                    }
                    result.success(null)
                } else {
                    result.error("INVALID_URL", "URL is null", null)
                }
            }
            "evaluateJavascript" -> {
                val script = call.argument<String>("script")
                if (script != null) {
                    val currentSession = tabManager.currentSession
                    if (currentSession != null) {
                        currentSession.loadUri("javascript:$script")
                    }
                    result.success(null)
                } else {
                    result.error("INVALID_SCRIPT", "Script is null", null)
                }
            }
            "postMessage" -> {
                val message = call.argument<String>("message")
                if (message != null) {
                    val currentSession = tabManager.currentSession
                    if (currentSession != null) {
                        currentSession.loadUri("javascript:if (window.onFlutterMessage) { window.onFlutterMessage($message); }")
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
                    val currentSession = tabManager.currentSession
                    if (currentSession != null) {
                        currentSession.loadUri("javascript:$js")
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
                val currentSession = tabManager.currentSession
                if (currentSession != null) {
                    currentSession.loadUri("javascript:$js")
                }
                result.success(null)
            }
            "closeCurrentTab" -> {
                val resultValue = tabManager.closeCurrentTab()
                result.success(resultValue)
            }
            "closeTab" -> {
                val tabId = call.argument<Long>("tabId")
                if (tabId != null) {
                    val resultValue = tabManager.closeTab(tabId)
                    result.success(resultValue)
                } else {
                    result.error("INVALID_TAB_ID", "Tab id is null", null)
                }
            }
            "goBackToPreviousTab" -> {
                val resultValue = tabManager.goBackToPreviousTab()
                result.success(resultValue)
            }
            "getTabsInfo" -> {
                result.success(tabManager.getTabsInfo())
            }
            "goBack" -> {
                Log.d("NyaNyaWebViewLog-Native", "goBack called, currentSession: ${tabManager.currentSession}")
                val currentSession = tabManager.currentSession
                currentSession?.goBack()
                result.success(null)
            }
            "goForward" -> {
                Log.d("NyaNyaWebViewLog-Native", "goForward called, currentSession: ${tabManager.currentSession}")
                val currentSession = tabManager.currentSession
                currentSession?.goForward()
                result.success(null)
            }
            "canGoBack" -> {
                Log.d("NyaNyaWebViewLog-Native", ">>> canGoBack called, currentTabCanGoBack: ${tabManager.currentTabCanGoBack}")
                result.success(tabManager.currentTabCanGoBack)
            }
            "canGoForward" -> {
                Log.d("NyaNyaWebViewLog-Native", ">>> canGoForward called, currentTabCanGoForward: ${tabManager.currentTabCanGoForward}")
                result.success(tabManager.currentTabCanGoForward)
            }
            "reload" -> {
                Log.d("NyaNyaWebViewLog-Native", "reload called, currentSession: ${tabManager.currentSession}")
                val currentSession = tabManager.currentSession
                currentSession?.reload()
                result.success(null)
            }
            "openInBrowser" -> {
                val url = call.argument<String>("url")
                if (url != null) {
                    Log.d("NyaNyaWebViewLog-Native", "openInBrowser called with url: $url, context: ${context}")
                    try {
                        val uri = android.net.Uri.parse(url)
                        Log.d("NyaNyaWebViewLog-Native", "Parsed URI: $uri")
                        val intent = android.content.Intent(android.content.Intent.ACTION_VIEW, uri)
                        intent.addFlags(android.content.Intent.FLAG_ACTIVITY_NEW_TASK)
                        Log.d("NyaNyaWebViewLog-Native", "Starting activity with intent: $intent")
                        context.startActivity(intent)
                        result.success(null)
                    } catch (e: Exception) {
                        Log.e("NyaNyaWebViewLog-Native", "Error opening in browser: ${e.message}", e)
                        result.error("OPEN_BROWSER_ERROR", e.message, null)
                    }
                } else {
                    Log.e("NyaNyaWebViewLog-Native", "openInBrowser called with null url")
                    result.error("INVALID_URL", "URL is null", null)
                }
            }
            "checkSessionsHealth" -> {
                Log.d("NyaNyaWebViewLog-Native", "checkSessionsHealth called, tabCount: ${tabManager.tabCount}")
                val sessionsValid = tabManager.tabStack.all { tab ->
                    try {
                        tab.session.isOpen
                    } catch (e: Exception) {
                        Log.e("NyaNyaWebViewLog-Native", "Session check failed: ${e.message}")
                        false
                    }
                }
                Log.d("NyaNyaWebViewLog-Native", "checkSessionsHealth result: $sessionsValid, tabCount: ${tabManager.tabCount}")
                result.success(sessionsValid && tabManager.tabCount > 0)
            }
            "shutdownGeckoRuntime" -> {
                Log.d("NyaNyaWebViewLog-Native", "shutdownGeckoRuntime called, preparing to shutdown GeckoRuntime")
                shutdownRuntime()
                result.success(null)
            }
            "checkWebViewReady" -> {
                Log.d("NyaNyaWebViewLog-Native", "checkWebViewReady called")
                try {
                    val runtimeExists = geckoRuntime != null && !isRuntimeShutdown
                    val sessionExists = tabManager.currentSession != null
                    val isSessionOpen = try {
                        tabManager.currentSession?.isOpen ?: false
                    } catch (e: Exception) {
                        Log.e("NyaNyaWebViewLog-Native", "Error checking if session is open", e)
                        false
                    }
                    val viewAttached = geckoView.isAttachedToWindow

                    val isReady = runtimeExists && sessionExists && isSessionOpen
                    Log.d("NyaNyaWebViewLog-Native", "GeckoView check: runtime=$runtimeExists, session=$sessionExists, open=$isSessionOpen, attached=$viewAttached, ready=$isReady")
                    result.success(isReady)
                } catch (e: Exception) {
                    Log.e("NyaNyaWebViewLog-Native", "Error checking GeckoView readiness", e)
                    result.success(false)
                }
            }
            else -> result.notImplemented()
        }
    }
}

class GeckoViewWrapper(context: Context) : GeckoView(context) {

    private val TAG = "GeckoViewWrapper"

    init {
        Log.d("NyaNyaWebViewLog-Native", "GeckoViewWrapper initialized")
        isFocusable = true
        isFocusableInTouchMode = true
        isClickable = true
        isFocusedByDefault = true
    }

    override fun onCheckIsTextEditor(): Boolean {
        Log.d("NyaNyaWebViewLog-Native", "onCheckIsTextEditor called, returning true")
        return true
    }

    override fun onCreateInputConnection(outAttrs: EditorInfo): InputConnection? {
        Log.d("NyaNyaWebViewLog-Native", "onCreateInputConnection called, delegating to super class")
        return super.onCreateInputConnection(outAttrs)
    }

    override fun checkInputConnectionProxy(view: View?): Boolean {
        Log.d("NyaNyaWebViewLog-Native", "checkInputConnectionProxy called")
        return true
    }

    fun showSoftInput() {
        Log.w("NyaNyaWebViewLog-Native", "========== showSoftInput() called ==========")
        val imm = context.getSystemService(Context.INPUT_METHOD_SERVICE) as? android.view.inputmethod.InputMethodManager
        if (imm != null) {
            val isActive = imm.isActive(this)
            Log.w("NyaNyaWebViewLog-Native", "hasFocus=${hasFocus()}, isFocused=${isFocused()}, isActive=$isActive")

            if (isActive) {
                Log.w("NyaNyaWebViewLog-Native", "SUCCESS: View IS active, showing soft input directly")
                imm.showSoftInput(this, 0)
            } else {
                Log.w("NyaNyaWebViewLog-Native", "PROBLEM: View has focus but NOT active (VirtualDisplay issue)")
                try {
                    Log.w("NyaNyaWebViewLog-Native", "Attempting reflection workaround")
                    val method = imm.javaClass.getMethod(
                        "showSoftInput",
                        android.view.View::class.java,
                        Int::class.javaPrimitiveType,
                        android.os.ResultReceiver::class.java
                    )
                    method.invoke(imm, this, 0, null)
                    Log.w("NyaNyaWebViewLog-Native", "Reflection call succeeded")
                } catch (e: Exception) {
                    Log.w("NyaNyaWebViewLog-Native", "Reflection failed: ${e.message}")
                    if (hasFocus()) {
                        Log.w("NyaNyaWebViewLog-Native", "Attempting fix: clearFocus() then requestFocus()")
                        clearFocus()
                        requestFocus()
                    }
                    post {
                        val newIsActive = imm.isActive(this)
                        Log.w("NyaNyaWebViewLog-Native", "After post: hasFocus=${hasFocus()}, isActive=$newIsActive")
                        if (hasFocus()) {
                            Log.w("NyaNyaWebViewLog-Native", "Calling showSoftInput after post")
                            imm.showSoftInput(this@GeckoViewWrapper, 0)
                        }
                    }
                }
            }
        } else {
            Log.w("NyaNyaWebViewLog-Native", "ERROR: InputMethodManager is null!")
        }
    }
}
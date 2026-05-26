package club.aiiko.nyanya_webview

import android.util.Log
import androidx.annotation.NonNull
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.embedding.engine.plugins.activity.ActivityAware
import io.flutter.embedding.engine.plugins.activity.ActivityPluginBinding
import io.flutter.plugin.common.MethodChannel

class NyanyaWebviewPlugin : FlutterPlugin, ActivityAware {
    private var methodChannel: MethodChannel? = null

    override fun onAttachedToEngine(@NonNull flutterPluginBinding: FlutterPlugin.FlutterPluginBinding) {
        Log.d("NyaNyaWebViewLog", "NyanyaWebviewPlugin.onAttachedToEngine STARTED")
        val messenger = flutterPluginBinding.binaryMessenger
        methodChannel = MethodChannel(messenger, "nyanya_webview")
        
        // 注册 GeckoView
        Log.d("NyaNyaWebViewLog", "NyanyaWebviewPlugin: Registering GeckoViewFactory")
        flutterPluginBinding.platformViewRegistry.registerViewFactory(
            "geckoView",
            GeckoViewFactory(messenger)
        )
        
        // 注册 SystemWebView
        Log.d("NyaNyaWebViewLog", "NyanyaWebviewPlugin: Registering SystemWebViewFactory")
        flutterPluginBinding.platformViewRegistry.registerViewFactory(
            "systemWebView",
            SystemWebViewFactory(messenger)
        )
        Log.d("NyaNyaWebViewLog", "NyanyaWebviewPlugin.onAttachedToEngine COMPLETED")
    }

    override fun onDetachedFromEngine(@NonNull binding: FlutterPlugin.FlutterPluginBinding) {
        methodChannel?.setMethodCallHandler(null)
        methodChannel = null
    }

    override fun onAttachedToActivity(binding: ActivityPluginBinding) {}

    override fun onDetachedFromActivityForConfigChanges() {}

    override fun onReattachedToActivityForConfigChanges(binding: ActivityPluginBinding) {}

    override fun onDetachedFromActivity() {}
}
package club.aiiko.nyanya_webview

import android.app.Activity
import android.content.Intent
import android.net.Uri
import android.util.Log
import androidx.annotation.NonNull
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.embedding.engine.plugins.activity.ActivityAware
import io.flutter.embedding.engine.plugins.activity.ActivityPluginBinding
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugin.common.PluginRegistry

class NyanyaWebviewPlugin : FlutterPlugin, ActivityAware, MethodChannel.MethodCallHandler {
    private var methodChannel: MethodChannel? = null
    private var activity: Activity? = null
    private val geckoViewPlatforms = mutableListOf<GeckoViewPlatform>()
    
    // 用于 SystemWebView 文件选择的回调
    private var pendingResult: MethodChannel.Result? = null
    private var pendingAllowMultiple: Boolean = false
    
    companion object {
        private const val REQUEST_CODE_PICK_FILE_SYSTEM = 1002
    }
    
    private val activityResultListener = PluginRegistry.ActivityResultListener { requestCode, resultCode, data ->
        Log.d("NyaNyaWebViewLog", "Plugin received onActivityResult")
        
        // 处理 GeckoView 的结果
        geckoViewPlatforms.forEach { it.onActivityResult(requestCode, resultCode, data) }
        
        // 处理 SystemWebView 的结果
        if (requestCode == REQUEST_CODE_PICK_FILE_SYSTEM) {
            handleSystemWebViewFileResult(resultCode, data)
        }
        
        true
    }

    override fun onAttachedToEngine(@NonNull flutterPluginBinding: FlutterPlugin.FlutterPluginBinding) {
        Log.d("NyaNyaWebViewLog", "NyanyaWebviewPlugin.onAttachedToEngine STARTED")
        val messenger = flutterPluginBinding.binaryMessenger
        methodChannel = MethodChannel(messenger, "nyanya_webview")
        methodChannel?.setMethodCallHandler(this)
        
        // 注册 GeckoView
        Log.d("NyaNyaWebViewLog", "NyanyaWebviewPlugin: Registering GeckoViewFactory")
        flutterPluginBinding.platformViewRegistry.registerViewFactory(
            "geckoView",
            GeckoViewFactory(messenger, this)
        )
        
        Log.d("NyaNyaWebViewLog", "NyanyaWebviewPlugin.onAttachedToEngine COMPLETED")
    }

    override fun onDetachedFromEngine(@NonNull binding: FlutterPlugin.FlutterPluginBinding) {
        methodChannel?.setMethodCallHandler(null)
        methodChannel = null
    }

    override fun onAttachedToActivity(binding: ActivityPluginBinding) {
        Log.d("NyaNyaWebViewLog", "NyanyaWebviewPlugin.onAttachedToActivity STARTED")
        activity = binding.activity
        binding.addActivityResultListener(activityResultListener)
        geckoViewPlatforms.forEach { it.updateActivity(activity) }
    }

    override fun onDetachedFromActivityForConfigChanges() {
        Log.d("NyaNyaWebViewLog", "NyanyaWebviewPlugin.onDetachedFromActivityForConfigChanges")
        activity = null
    }

    override fun onReattachedToActivityForConfigChanges(binding: ActivityPluginBinding) {
        Log.d("NyaNyaWebViewLog", "NyanyaWebviewPlugin.onReattachedToActivityForConfigChanges")
        activity = binding.activity
        binding.addActivityResultListener(activityResultListener)
        geckoViewPlatforms.forEach { it.updateActivity(activity) }
    }

    override fun onDetachedFromActivity() {
        Log.d("NyaNyaWebViewLog", "NyanyaWebviewPlugin.onDetachedFromActivity")
        activity = null
    }
    
    fun registerGeckoViewPlatform(platform: GeckoViewPlatform) {
        Log.d("NyaNyaWebViewLog", "Registering GeckoViewPlatform: $platform")
        geckoViewPlatforms.add(platform)
        if (activity != null) {
            platform.updateActivity(activity)
        }
    }
    
    fun unregisterGeckoViewPlatform(platform: GeckoViewPlatform) {
        Log.d("NyaNyaWebViewLog", "Unregistering GeckoViewPlatform: $platform")
        geckoViewPlatforms.remove(platform)
    }
    
    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "pickFilesForSystemWebView" -> {
                val mimeTypes = call.argument<List<String>>("mimeTypes")
                val allowMultiple = call.argument<Boolean>("allowMultiple") ?: false
                Log.d("NyaNyaWebViewLog", "pickFilesForSystemWebView called, mimeTypes=$mimeTypes, allowMultiple=$allowMultiple")
                pickFilesForSystemWebView(mimeTypes, allowMultiple, result)
            }
            else -> {
                result.notImplemented()
            }
        }
    }
    
    private fun pickFilesForSystemWebView(mimeTypes: List<String>?, allowMultiple: Boolean, result: MethodChannel.Result) {
        val currentActivity = activity ?: run {
            Log.e("NyaNyaWebViewLog", "No activity available, cannot start file picker")
            result.success(listOf<String>())
            return
        }
        
        pendingResult = result
        pendingAllowMultiple = allowMultiple
        
        val intent = Intent(Intent.ACTION_GET_CONTENT).apply {
            addCategory(Intent.CATEGORY_OPENABLE)
            type = "*/*"
            addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
            
            if (mimeTypes != null && mimeTypes.isNotEmpty()) {
                putExtra(Intent.EXTRA_MIME_TYPES, mimeTypes.toTypedArray())
            }
            
            if (allowMultiple && android.os.Build.VERSION.SDK_INT >= android.os.Build.VERSION_CODES.JELLY_BEAN_MR2) {
                putExtra(Intent.EXTRA_ALLOW_MULTIPLE, true)
            }
        }
        
        currentActivity.startActivityForResult(intent, REQUEST_CODE_PICK_FILE_SYSTEM)
    }
    
    private fun handleSystemWebViewFileResult(resultCode: Int, data: Intent?) {
        val result = pendingResult ?: return
        
        if (resultCode == Activity.RESULT_OK && data != null) {
            val uris = mutableListOf<String>()
            data.clipData?.let { clipData ->
                for (i in 0 until clipData.itemCount) {
                    uris.add(clipData.getItemAt(i).uri.toString())
                }
            } ?: run {
                data.data?.let { uris.add(it.toString()) }
            }
            
            Log.d("NyaNyaWebViewLog", "SystemWebView selected ${uris.size} files, uris=$uris")
            result.success(uris)
        } else {
            Log.d("NyaNyaWebViewLog", "SystemWebView file picker canceled")
            result.success(listOf<String>())
        }
        
        pendingResult = null
        pendingAllowMultiple = false
    }
}
package club.aiiko.nyanya_webview

import android.content.Context
import android.util.Log
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.StandardMessageCodec
import io.flutter.plugin.platform.PlatformView
import io.flutter.plugin.platform.PlatformViewFactory

class GeckoViewFactory(private val messenger: BinaryMessenger) : PlatformViewFactory(StandardMessageCodec.INSTANCE) {
    override fun create(context: Context, viewId: Int, args: Any?): PlatformView {
        Log.d("NyaNyaWebViewLog", "GeckoViewFactory.create called! viewId=$viewId, args=$args")
        return GeckoViewPlatform(context, messenger, viewId, args as Map<String, Any>?)
    }
}
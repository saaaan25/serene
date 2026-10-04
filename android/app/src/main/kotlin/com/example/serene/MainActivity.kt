package com.example.serene

import io.flutter.embedding.engine.FlutterEngine
import io.flutter.embedding.android.FlutterFragmentActivity
import io.flutter.plugin.common.MethodChannel
import org.tensorflow.lite.flex.FlexDelegate

class MainActivity : FlutterFragmentActivity() {
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            FLEX_DELEGATE_CHANNEL,
        ).setMethodCallHandler { call, result ->
            when (call.method) {
                "createFlexDelegate" -> {
                    try {
                        val delegate = FlexDelegateHolder.delegate
                            ?: FlexDelegate().also { FlexDelegateHolder.delegate = it }
                        result.success(delegate.nativeHandle)
                    } catch (error: Exception) {
                        result.error(
                            "flex_delegate_init_failed",
                            "Could not initialize TensorFlow Select Ops: ${error.message}",
                            null,
                        )
                    }
                }
                "disposeFlexDelegate" -> {
                    FlexDelegateHolder.delegate?.close()
                    FlexDelegateHolder.delegate = null
                    result.success(null)
                }
                else -> result.notImplemented()
            }
        }
    }

    private companion object {
        const val FLEX_DELEGATE_CHANNEL = "com.example.serene/tflite_flex"
    }
}

private object FlexDelegateHolder {
    var delegate: FlexDelegate? = null
}

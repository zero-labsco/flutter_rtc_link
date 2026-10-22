package com.zerolabsco.rtc_link

import android.app.Activity
import android.content.Intent
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.embedding.engine.plugins.activity.ActivityAware
import io.flutter.embedding.engine.plugins.activity.ActivityPluginBinding
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugin.common.PluginRegistry

/**
 * Flutter RTC Link Android plugin entry point.
 * Flutter RTC Link Android 插件入口。
 *
 * Method channel `com.zerolabsco.rtc_link/methods` (snake_case names) plus an
 * event channel `com.zerolabsco.rtc_link/events` for native progress events.
 * Method channel `com.zerolabsco.rtc_link/methods`（snake_case 方法名），另有事件通道
 * `com.zerolabsco.rtc_link/events` 用于原生进度事件。
 *
 * Methods / 方法:
 * - `dppSupported` → Boolean
 * - `dppStart` {qrContent} → Boolean (launches the system Settings DPP flow)
 *   （启动系统设置 DPP 流程）
 * - `foregroundServiceStart` {title, text} → void
 * - `foregroundServiceStop` → void
 */
class RtcLinkPlugin : FlutterPlugin, ActivityAware, MethodChannel.MethodCallHandler,
    PluginRegistry.ActivityResultListener {

    private lateinit var methodChannel: MethodChannel
    private lateinit var eventChannel: EventChannel
    private var eventSink: EventChannel.EventSink? = null

    private var appContext: android.content.Context? = null
    private var activity: Activity? = null
    private var activityBinding: ActivityPluginBinding? = null

    private val dppManager: DppManager by lazy {
        DppManager(requireNotNull(appContext) { "context not attached" })
    }

    // Pending DPP result callback. / 待处理的 DPP 结果回调。
    private var pendingDppResult: MethodChannel.Result? = null

    private val dppRequestCode = 0x5254 // 'RT'

    override fun onAttachedToEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        appContext = binding.applicationContext
        methodChannel = MethodChannel(binding.binaryMessenger, "com.zerolabsco.rtc_link/methods")
        methodChannel.setMethodCallHandler(this)
        eventChannel = EventChannel(binding.binaryMessenger, "com.zerolabsco.rtc_link/events")
        eventChannel.setStreamHandler(object : EventChannel.StreamHandler {
            override fun onListen(arguments: Any?, events: EventChannel.EventSink?) {
                eventSink = events
            }

            override fun onCancel(arguments: Any?) {
                eventSink = null
            }
        })
    }

    override fun onDetachedFromEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        methodChannel.setMethodCallHandler(null)
        eventChannel.setStreamHandler(null)
        appContext = null
    }

    // ---------- ActivityAware ----------

    override fun onAttachedToActivity(binding: ActivityPluginBinding) {
        activity = binding.activity
        activityBinding = binding
        binding.addActivityResultListener(this)
    }

    override fun onDetachedFromActivity() {
        activityBinding?.removeActivityResultListener(this)
        activityBinding = null
        activity = null
    }

    override fun onReattachedToActivityForConfigChanges(binding: ActivityPluginBinding) {
        onAttachedToActivity(binding)
    }

    override fun onDetachedFromActivityForConfigChanges() {
        onDetachedFromActivity()
    }

    // ---------- MethodChannel ----------

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "dppSupported" -> result.success(dppManager.isEasyConnectSupported())

            "dppStart" -> {
                val qrContent = call.argument<String>("qrContent")
                if (qrContent.isNullOrEmpty()) {
                    result.error("invalid_argument", "qrContent is required", null)
                    return
                }
                startDpp(qrContent, result)
            }

            "foregroundServiceStart" -> {
                val title = call.argument<String>("title") ?: "RTC Link"
                val text = call.argument<String>("text") ?: "Recording in progress"
                RtcLinkForegroundService.start(requireNotNull(appContext), title, text)
                result.success(null)
            }

            "foregroundServiceStop" -> {
                RtcLinkForegroundService.stop(requireNotNull(appContext))
                result.success(null)
            }

            else -> result.notImplemented()
        }
    }

    /**
     * Launches the system Wi-Fi Easy Connect (DPP) configurator.
     * 启动系统 Wi-Fi Easy Connect（DPP）配置器。
     *
     * The DPP URI is passed as the intent DATA (scheme `DPP`) — not as an
     * extra — per the platform contract (API 29+).
     * DPP URI 通过 intent DATA（scheme `DPP`）传递——不是 extra——这是平台契约
     * （API 29+）。
     */
    private fun startDpp(qrContent: String, result: MethodChannel.Result) {
        val currentActivity = activity
        if (currentActivity == null) {
            result.error(
                "no_activity",
                "DPP needs a foreground Activity to launch the system Settings flow.",
                null,
            )
            return
        }
        if (!dppManager.isEasyConnectSupported()) {
            result.error(
                "unsupported",
                "Wi-Fi Easy Connect (DPP) is not supported on this device.",
                null,
            )
            return
        }
        val intent = dppManager.buildProcessUriIntent(qrContent)
        if (intent == null) {
            result.error(
                "no_resolver",
                "No system Activity handles ACTION_PROCESS_WIFI_EASY_CONNECT_URI.",
                null,
            )
            return
        }
        pendingDppResult = result
        currentActivity.startActivityForResult(intent, dppRequestCode)
    }

    override fun onActivityResult(
        requestCode: Int,
        resultCode: Int,
        data: Intent?,
    ): Boolean {
        if (requestCode != dppRequestCode) return false
        val pending = pendingDppResult ?: return true
        pendingDppResult = null
        when (resultCode) {
            Activity.RESULT_OK -> {
                val ssid = data?.getStringExtra(
                    android.provider.Settings.EXTRA_EASY_CONNECT_ATTEMPTED_SSID,
                )
                emitNativeEvent(mapOf("type" to "dppCompleted", "ssid" to ssid))
                pending.success(true)
            }

            Activity.RESULT_CANCELED -> {
                val errorCode = data?.getIntExtra(
                    android.provider.Settings.EXTRA_EASY_CONNECT_ERROR_CODE,
                    -1,
                ) ?: -1
                emitNativeEvent(mapOf("type" to "dppFailed", "errorCode" to errorCode))
                pending.error(
                    "dpp_failed",
                    "Wi-Fi Easy Connect failed (errorCode=$errorCode).",
                    null,
                )
            }

            else -> {
                pending.error("dpp_failed", "Unexpected DPP result code $resultCode.", null)
            }
        }
        return true
    }

    private fun emitNativeEvent(payload: Map<String, Any?>) {
        // Native events are emitted on the platform thread; the EventChannel
        // handoff delivers them on the main thread.
        // 原生事件在平台线程发出；EventChannel 交接后由主线程投递。
        eventSink?.success(payload)
    }
}

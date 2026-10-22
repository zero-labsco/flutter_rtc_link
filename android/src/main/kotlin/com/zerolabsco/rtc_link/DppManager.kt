package com.zerolabsco.rtc_link

import android.content.Context
import android.content.Intent
import android.net.Uri
import android.net.wifi.WifiManager
import android.os.Build
import android.provider.Settings

/**
 * Wi-Fi Easy Connect (DPP) helper.
 * Wi-Fi Easy Connect（DPP）助手。
 *
 * Important platform reality (verified against the Android 10+ docs):
 * the `WifiManager` Easy Connect APIs (`startEasyConnectAsConfiguratorInitiator`,
 * …) are `@SystemApi` and require `NETWORK_SETTINGS` /
 * `NETWORK_SETUP_WIZARD`, so ordinary third-party apps CANNOT call them. The
 * supported path for apps is:
 *   1. `WifiManager.isEasyConnectSupported()` (public, API 29+), then
 *   2. launch `Settings.ACTION_PROCESS_WIFI_EASY_CONNECT_URI` with the DPP URI
 *      as the intent DATA (scheme `DPP`), and read the result from
 *      `onActivityResult` (RESULT_OK = provisioned, RESULT_CANCELED = failed).
 * DPP needs no runtime permission.
 *
 * 重要平台事实（已对照 Android 10+ 文档核实）：
 * `WifiManager` 的 Easy Connect 系列 API（`startEasyConnectAsConfiguratorInitiator`
 * 等）是 `@SystemApi`，需要 `NETWORK_SETTINGS` / `NETWORK_SETUP_WIZARD` 权限，
 * 普通第三方应用无法调用。应用侧受支持的路径是：
 *   1. `WifiManager.isEasyConnectSupported()`（公开 API，API 29+），然后
 *   2. 启动 `Settings.ACTION_PROCESS_WIFI_EASY_CONNECT_URI`，DPP URI 作为
 *      intent DATA（scheme `DPP`）传入，结果从 `onActivityResult` 读取
 *      （RESULT_OK = 配网成功，RESULT_CANCELED = 失败）。
 * DPP 不需要任何运行时权限。
 */
class DppManager(private val context: Context) {

    private val wifiManager: WifiManager? by lazy {
        context.applicationContext.getSystemService(Context.WIFI_SERVICE) as? WifiManager
    }

    /** Whether this device supports Wi-Fi Easy Connect (API 29+). / 本设备是否支持 Wi-Fi Easy Connect（API 29+）。 */
    fun isEasyConnectSupported(): Boolean {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.Q) return false
        return try {
            wifiManager?.isEasyConnectSupported ?: false
        } catch (_: NoSuchMethodError) {
            // OEM images without the framework method / 没有该框架方法的 OEM 镜像
            false
        }
    }

    /**
     * Builds the system DPP intent for [qrContent].
     * 为 [qrContent] 构建系统 DPP 意图。
     *
     * Returns `null` when no system Activity can handle the intent.
     * 当没有系统 Activity 能处理该意图时返回 `null`。
     */
    fun buildProcessUriIntent(qrContent: String): Intent? {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.Q) return null
        val intent = Intent(Settings.ACTION_PROCESS_WIFI_EASY_CONNECT_URI).apply {
            // The DPP URI is the intent DATA, never an extra (platform contract).
            // DPP URI 是 intent DATA，绝不是 extra（平台契约）。
            data = Uri.parse(qrContent)
            addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
        }
        val resolved = context.packageManager.queryIntentActivities(intent, 0)
        if (resolved.isEmpty()) return null
        return intent
    }
}

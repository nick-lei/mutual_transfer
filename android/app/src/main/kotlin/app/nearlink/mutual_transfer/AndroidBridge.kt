package app.nearlink.mutual_transfer

import android.Manifest
import android.app.Activity
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.BroadcastReceiver
import android.content.ActivityNotFoundException
import android.content.ClipData
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.media.AudioAttributes
import android.media.RingtoneManager
import android.net.Uri
import android.net.wifi.WifiManager
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.provider.OpenableColumns
import android.provider.Settings
import android.webkit.MimeTypeMap
import androidx.core.app.NotificationCompat
import androidx.core.content.FileProvider
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.io.File
import java.security.MessageDigest
import java.util.UUID
import java.util.concurrent.Executors

class AndroidBridge(private val app: NearLinkApplication, messenger: BinaryMessenger) : MethodChannel.MethodCallHandler {
    private val channel = MethodChannel(messenger, "nearlink/android")
    private val main = Handler(Looper.getMainLooper())
    private val io = Executors.newSingleThreadExecutor()
    private val manager = app.getSystemService(NotificationManager::class.java)
    private val preferences = app.getSharedPreferences("nearlink-mobile", Context.MODE_PRIVATE)
    private val pendingShares = mutableListOf<Map<String, Any?>>()
    private val pendingActions = mutableListOf<Map<String, String>>()
    private var ready = false
    private var notificationsReady = false
    private var permissionReply: MethodChannel.Result? = null
    private var exportReply: MethodChannel.Result? = null
    private var exportSource: File? = null
    private var foreground = true
    private var multicast: WifiManager.MulticastLock? = null
    private val apkInstaller = ApkInstallFlow(
        canInstall = { app.packageManager.canRequestPackageInstalls() },
        requestPermission = {
            val host = activity ?: error("请返回邻传后打开安装包")
            try {
                host.startActivityForResult(
                    Intent(Settings.ACTION_MANAGE_UNKNOWN_APP_SOURCES, Uri.parse("package:${app.packageName}")),
                    INSTALL_PERMISSION,
                )
            } catch (_: ActivityNotFoundException) {
                error("无法打开授权页面，请在手机设置中允许邻传安装未知应用后重试")
            }
        },
        launchInstaller = { source ->
            val file = checkedFile(source.path)
            val uri = FileProvider.getUriForFile(app, "${app.packageName}.files", file)
            val intent = Intent(Intent.ACTION_VIEW).setDataAndType(uri, "application/vnd.android.package-archive")
                .addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
                .apply { clipData = ClipData.newRawUri("APK", uri) }
            try {
                openActivity(intent)
            } catch (_: ActivityNotFoundException) {
                error("当前手机未提供可用的应用安装器，可将安装包另存到手机后重试")
            }
        },
    )
    var activity: MainActivity? = null
    var activeTransfers = 0
        private set
    val backgroundEnabled get() = preferences.getBoolean("background", false)

    init {
        channel.setMethodCallHandler(this)
        for ((id, name) in listOf("files" to "文件接收请求", "messages" to "新消息", "completion" to "传输完成")) {
            manager.createNotificationChannel(NotificationChannel(id, name, NotificationManager.IMPORTANCE_DEFAULT))
        }
        manager.createNotificationChannel(NotificationChannel("background", "后台接收服务", NotificationManager.IMPORTANCE_LOW))
    }

    override fun onMethodCall(call: MethodCall, reply: MethodChannel.Result) {
        try {
            when (call.method) {
                "paths" -> reply.success(mapOf(
                    "dataDirectory" to File(app.filesDir, "NearLink").path,
                    "receiveDirectory" to File(app.filesDir, "Received").path,
                    "deviceName" to Build.MODEL,
                    "backgroundEnabled" to backgroundEnabled,
                ))
                "ready" -> {
                    ready = true
                    reply.success(pendingShares.toList())
                    pendingShares.clear()
                }
                "initializeNotifications" -> {
                    notificationsReady = true
                    reply.success(pendingActions.toList())
                    pendingActions.clear()
                }
                "notificationsAllowed" -> reply.success(manager.areNotificationsEnabled())
                "requestNotifications" -> requestNotifications(reply)
                "showNotification" -> {
                    showNotification(call)
                    reply.success(null)
                }
                "dismissNotification" -> {
                    manager.cancel(call.argument<String>("id"), 1)
                    reply.success(null)
                }
                "notificationSettings" -> {
                    openActivity(Intent(Settings.ACTION_APP_NOTIFICATION_SETTINGS).putExtra(Settings.EXTRA_APP_PACKAGE, app.packageName))
                    reply.success(null)
                }
                "playSound" -> {
                    val sound = RingtoneManager.getRingtone(app, RingtoneManager.getDefaultUri(RingtoneManager.TYPE_NOTIFICATION))
                    sound?.audioAttributes = AudioAttributes.Builder().setUsage(AudioAttributes.USAGE_NOTIFICATION).build()
                    sound?.play()
                    reply.success(null)
                }
                "setBackground" -> {
                    setBackground(call.argument<Boolean>("enabled") == true)
                    reply.success(null)
                }
                "setForeground" -> {
                    foreground = call.argument<Boolean>("foreground") == true
                    updateMulticast()
                    reply.success(null)
                }
                "setActiveTransfers" -> {
                    activeTransfers = call.argument<Int>("count") ?: 0
                    NearLinkService.current?.updateState()
                    reply.success(null)
                }
                "showApp" -> {
                    openActivity(Intent(app, MainActivity::class.java))
                    reply.success(null)
                }
                "openFile", "shareFile" -> {
                    val file = checkedFile(call.argument<String>("path")!!)
                    if (call.method == "openFile" && file.extension.equals("apk", ignoreCase = true)) {
                        apkInstaller.open(file) { error ->
                            if (error == null) reply.success(null)
                            else reply.error("apk_install_failed", error, null)
                        }
                        return
                    }
                    val uri = FileProvider.getUriForFile(app, "${app.packageName}.files", file)
                    val mime = MimeTypeMap.getSingleton().getMimeTypeFromExtension(file.extension.lowercase()) ?: "application/octet-stream"
                    val intent = if (call.method == "shareFile") {
                        Intent.createChooser(Intent(Intent.ACTION_SEND).setType(mime).putExtra(Intent.EXTRA_STREAM, uri)
                            .addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION), "分享文件")
                    } else {
                        Intent(Intent.ACTION_VIEW).setDataAndType(uri, mime).addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
                    }
                    openActivity(intent)
                    reply.success(null)
                }
                "exportFile" -> {
                    val host = activity ?: error("请返回邻传后重试")
                    check(exportReply == null) { "另一个保存窗口尚未关闭" }
                    val file = checkedFile(call.argument<String>("path")!!)
                    exportSource = file
                    exportReply = reply
                    host.startActivityForResult(Intent(Intent.ACTION_CREATE_DOCUMENT).addCategory(Intent.CATEGORY_OPENABLE)
                        .setType("application/octet-stream").putExtra(Intent.EXTRA_TITLE, file.name), EXPORT)
                }
                else -> reply.notImplemented()
            }
        } catch (exception: Exception) {
            if (exportReply === reply) { exportReply = null; exportSource = null }
            reply.error("android_operation_failed", exception.message ?: "系统操作未完成", null)
        }
    }

    private fun checkedFile(path: String): File {
        val file = File(path).canonicalFile
        check(listOf(app.filesDir, app.cacheDir).any { file.path.startsWith(it.canonicalPath + File.separator) }) {
            "文件不在邻传的可分享目录中"
        }
        check(file.isFile) { "文件已被移动或删除" }
        return file
    }

    private fun openActivity(intent: Intent) {
        if (activity != null) activity!!.startActivity(intent)
        else app.startActivity(intent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK))
    }

    private fun requestNotifications(reply: MethodChannel.Result) {
        if (Build.VERSION.SDK_INT < 33 || app.checkSelfPermission(Manifest.permission.POST_NOTIFICATIONS) == PackageManager.PERMISSION_GRANTED) {
            reply.success(manager.areNotificationsEnabled())
            return
        }
        check(permissionReply == null) { "通知权限请求正在进行" }
        val host = activity ?: error("请返回邻传后开启通知权限")
        permissionReply = reply
        host.requestPermissions(arrayOf(Manifest.permission.POST_NOTIFICATIONS), NOTIFICATIONS)
    }

    fun permissionResult(code: Int) {
        if (code != NOTIFICATIONS) return
        permissionReply?.success(manager.areNotificationsEnabled())
        permissionReply = null
    }

    fun activityResult(code: Int, result: Int, intent: Intent?): Boolean {
        if (code == INSTALL_PERMISSION) {
            apkInstaller.permissionReturned()
            return true
        }
        if (code != EXPORT) return false
        val reply = exportReply ?: return true
        val source = exportSource
        exportReply = null
        exportSource = null
        val uri = intent?.data
        if (result != Activity.RESULT_OK || uri == null || source == null) {
            reply.success(false)
            return true
        }
        io.execute {
            try {
                app.contentResolver.openOutputStream(uri, "w").use { output ->
                    check(output != null) { "无法写入这个保存位置" }
                    source.inputStream().use { it.copyTo(output, 1024 * 1024) }
                }
                main.post { reply.success(true) }
            } catch (exception: Exception) {
                main.post { reply.error("export_failed", "保存失败：${exception.message}", null) }
            }
        }
        return true
    }

    fun setBackground(enabled: Boolean) {
        if (enabled) app.startForegroundService(Intent(app, NearLinkService::class.java))
        else app.stopService(Intent(app, NearLinkService::class.java))
        preferences.edit().putBoolean("background", enabled).apply()
        updateMulticast()
    }

    fun backgroundStopped() {
        preferences.edit().putBoolean("background", false).apply()
        updateMulticast()
        channel.invokeMethod("backgroundStopped", null)
    }

    private fun updateMulticast() {
        if (foreground || backgroundEnabled) {
            if (multicast?.isHeld != true) {
                val wifi = app.getSystemService(Context.WIFI_SERVICE) as WifiManager
                multicast = wifi.createMulticastLock("NearLink:discovery").apply {
                    setReferenceCounted(false)
                    acquire()
                }
            }
        } else {
            if (multicast?.isHeld == true) multicast?.release()
            multicast = null
        }
    }

    private fun requestCode(id: String, action: String): Int =
        (MessageDigest.getInstance("SHA-256").digest("$id:$action".toByteArray()).take(4)
            .fold(0) { value, byte -> (value shl 8) or (byte.toInt() and 255) }) and Int.MAX_VALUE

    private fun notificationIntent(id: String, action: String, broadcast: Boolean): PendingIntent {
        val intent = Intent(app, if (broadcast) NotificationActionReceiver::class.java else MainActivity::class.java)
            .putExtra("nearlinkId", id).putExtra("nearlinkAction", action)
        val flags = PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        return if (broadcast) PendingIntent.getBroadcast(app, requestCode(id, action), intent, flags)
        else PendingIntent.getActivity(app, requestCode(id, action), intent, flags)
    }

    private fun showNotification(call: MethodCall) {
        val id = call.argument<String>("id")!!
        val builder = NotificationCompat.Builder(app, call.argument<String>("kind")!!)
            .setSmallIcon(R.drawable.ic_stat_nearlink)
            .setColor(0xff2463eb.toInt())
            .setContentTitle(call.argument<String>("title"))
            .setContentText(call.argument<String>("body"))
            .setStyle(NotificationCompat.BigTextStyle().bigText(call.argument<String>("body")))
            .setContentIntent(notificationIntent(id, "open", false))
            .setSilent(call.argument<Boolean>("sound") != true)
            .setAutoCancel(true)
            .setOnlyAlertOnce(false)
        if (call.argument<String>("kind") == "files") {
            builder.addAction(0, "拒绝", notificationIntent(id, "reject", true))
            builder.addAction(0, "接收", notificationIntent(id, "accept", true))
        }
        manager.notify(id, 1, builder.build())
    }

    fun notificationAction(id: String, action: String) {
        val data = mapOf("id" to id, "action" to action)
        if (notificationsReady) channel.invokeMethod("notificationAction", data)
        else pendingActions.add(data)
    }

    @Suppress("DEPRECATION")
    fun handleIntent(intent: Intent) {
        val id = intent.getStringExtra("nearlinkId")
        if (id != null) {
            notificationAction(id, intent.getStringExtra("nearlinkAction") ?: "open")
            intent.removeExtra("nearlinkId")
        }
        if (intent.action != Intent.ACTION_SEND && intent.action != Intent.ACTION_SEND_MULTIPLE) return
        val uris = if (intent.action == Intent.ACTION_SEND_MULTIPLE) {
            intent.getParcelableArrayListExtra<Uri>(Intent.EXTRA_STREAM).orEmpty()
        } else listOfNotNull(intent.getParcelableExtra<Uri>(Intent.EXTRA_STREAM))
        val text = intent.getCharSequenceExtra(Intent.EXTRA_TEXT)?.toString()
        intent.action = Intent.ACTION_MAIN
        io.execute {
            val paths = mutableListOf<String>()
            var failure: String? = null
            try {
                check(uris.size <= 1000) { "单次最多发送 1000 个文件" }
                val directory = File(app.cacheDir, "shared/${UUID.randomUUID()}").apply { mkdirs() }
                for ((index, uri) in uris.withIndex()) {
                    var name = "shared-${index + 1}"
                    app.contentResolver.query(uri, arrayOf(OpenableColumns.DISPLAY_NAME), null, null, null)?.use { cursor ->
                        if (cursor.moveToFirst()) name = cursor.getString(0) ?: name
                    }
                    name = name.replace(Regex("[\\\\/:*?\"<>|\\p{Cntrl}]"), "_").take(160)
                    if (name.isBlank() || name == "." || name == "..") name = "shared-${index + 1}"
                    val file = File(File(directory, index.toString()).apply { mkdirs() }, name)
                    app.contentResolver.openInputStream(uri).use { input ->
                        check(input != null) { "无法读取分享的文件" }
                        file.outputStream().use { input.copyTo(it, 1024 * 1024) }
                    }
                    paths.add(file.path)
                }
            } catch (exception: Exception) {
                failure = "部分分享文件未能读取：${exception.message}"
            }
            val data = mapOf("paths" to paths, "text" to text?.take(16000), "error" to failure)
            main.post {
                if (ready) channel.invokeMethod("sharedContent", data)
                else pendingShares.add(data)
            }
        }
    }

    companion object {
        private const val EXPORT = 7302
        private const val NOTIFICATIONS = 7303
        private const val INSTALL_PERMISSION = 7304
    }
}

class NotificationActionReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        val id = intent.getStringExtra("nearlinkId") ?: return
        (context.applicationContext as NearLinkApplication).bridge
            .notificationAction(id, intent.getStringExtra("nearlinkAction") ?: "open")
    }
}

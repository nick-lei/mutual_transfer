package app.nearlink.mutual_transfer

import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Service
import android.content.Intent
import android.os.Handler
import android.os.IBinder
import android.os.Looper
import android.os.PowerManager
import androidx.core.app.NotificationCompat

class NearLinkService : Service() {
    private val bridge get() = (application as NearLinkApplication).bridge
    private val handler = Handler(Looper.getMainLooper())
    private var wake: PowerManager.WakeLock? = null
    private val refresh = object : Runnable {
        override fun run() {
            updateState()
            handler.postDelayed(this, 5 * 60 * 1000L)
        }
    }

    override fun onCreate() {
        super.onCreate()
        current = this
        wake = getSystemService(PowerManager::class.java).newWakeLock(PowerManager.PARTIAL_WAKE_LOCK, "NearLink:transfer")
            .apply { setReferenceCounted(false) }
        startForeground(NOTIFICATION, notification())
        handler.post(refresh)
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        if (intent?.action == "stop") {
            bridge.backgroundStopped()
            stopSelf()
        }
        return START_NOT_STICKY
    }

    private fun notification() = NotificationCompat.Builder(this, "background")
        .setSmallIcon(R.drawable.ic_stat_nearlink)
        .setContentTitle("邻传 · 后台接收已开启")
        .setContentText(if (bridge.activeTransfers > 0) "${bridge.activeTransfers} 个文件正在传输" else "等待局域网中的文件和消息")
        .setContentIntent(PendingIntent.getActivity(this, 500, Intent(this, MainActivity::class.java),
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE))
        .setOngoing(true)
        .setSilent(true)
        .addAction(0, "停止后台接收", PendingIntent.getService(this, 501,
            Intent(this, NearLinkService::class.java).setAction("stop"),
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE))
        .build()

    fun updateState() {
        if (bridge.activeTransfers > 0) wake?.acquire(10 * 60 * 1000L)
        else if (wake?.isHeld == true) wake?.release()
        getSystemService(NotificationManager::class.java).notify(NOTIFICATION, notification())
    }

    override fun onDestroy() {
        handler.removeCallbacksAndMessages(null)
        if (wake?.isHeld == true) wake?.release()
        wake = null
        current = null
        super.onDestroy()
    }

    override fun onBind(intent: Intent?): IBinder? = null

    companion object {
        private const val NOTIFICATION = 500
        var current: NearLinkService? = null
            private set
    }
}

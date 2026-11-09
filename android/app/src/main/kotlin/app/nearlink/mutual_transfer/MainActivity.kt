package app.nearlink.mutual_transfer

import android.content.Context
import android.content.Intent
import android.os.Bundle
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine

class MainActivity : FlutterActivity() {
    private val bridge get() = (application as NearLinkApplication).bridge
    override fun provideFlutterEngine(context: Context): FlutterEngine =
        (application as NearLinkApplication).engine
    override fun shouldDestroyEngineWithHost() = false

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        bridge.activity = this
        if (savedInstanceState == null) bridge.handleIntent(intent)
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        setIntent(intent)
        bridge.handleIntent(intent)
    }

    @Deprecated("Activity result bridge for the document picker")
    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        if (!bridge.activityResult(requestCode, resultCode, data)) {
            super.onActivityResult(requestCode, resultCode, data)
        }
    }

    override fun onRequestPermissionsResult(code: Int, permissions: Array<out String>, results: IntArray) {
        super.onRequestPermissionsResult(code, permissions, results)
        bridge.permissionResult(code)
    }

    override fun onDestroy() {
        if (bridge.activity === this) bridge.activity = null
        super.onDestroy()
    }
}

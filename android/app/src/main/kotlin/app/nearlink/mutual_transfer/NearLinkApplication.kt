package app.nearlink.mutual_transfer

import android.app.Application
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.embedding.engine.dart.DartExecutor

class NearLinkApplication : Application() {
    lateinit var engine: FlutterEngine
        private set
    lateinit var bridge: AndroidBridge
        private set

    override fun onCreate() {
        super.onCreate()
        engine = FlutterEngine(this)
        bridge = AndroidBridge(this, engine.dartExecutor.binaryMessenger)
        engine.dartExecutor.executeDartEntrypoint(DartExecutor.DartEntrypoint.createDefault())
    }
}

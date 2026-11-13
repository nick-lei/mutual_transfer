package app.nearlink.mutual_transfer

import java.io.File

internal class ApkInstallFlow(
    private val canInstall: () -> Boolean,
    private val requestPermission: () -> Unit,
    private val launchInstaller: (File) -> Unit,
) {
    private data class Request(val file: File, val complete: (String?) -> Unit)
    private var pending: Request? = null

    fun open(file: File, complete: (String?) -> Unit) {
        if (pending != null) {
            complete("请先完成当前安装权限设置，再打开其他安装包")
            return
        }
        val request = Request(file, complete)
        try {
            if (canInstall()) {
                launch(request)
            } else {
                pending = request
                requestPermission()
            }
        } catch (exception: Exception) {
            pending = null
            complete(exception.message ?: "无法打开安装权限设置，请稍后重试")
        }
    }

    fun permissionReturned() {
        val request = pending ?: return
        pending = null
        try {
            // The settings activity can return RESULT_CANCELED even after granting access.
            if (canInstall()) {
                launch(request)
            } else {
                request.complete("安装权限未开启，请允许邻传安装未知应用后重试")
            }
        } catch (exception: Exception) {
            request.complete(exception.message ?: "无法检查安装权限，请重新打开安装包")
        }
    }

    private fun launch(request: Request) {
        try {
            launchInstaller(request.file)
            request.complete(null)
        } catch (exception: Exception) {
            request.complete(exception.message ?: "无法打开应用安装器，请稍后重试")
        }
    }
}

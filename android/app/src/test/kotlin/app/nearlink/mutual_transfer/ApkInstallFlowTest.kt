package app.nearlink.mutual_transfer

import java.io.File
import org.junit.Assert.*
import org.junit.Test

class ApkInstallFlowTest {
    private val first = File("received.apk")
    private val second = File("another.apk")

    @Test fun authorizedRequestOpensTheInstallerDirectly() {
        val launched = mutableListOf<File>()
        val results = mutableListOf<String?>()
        val flow = ApkInstallFlow({ true }, { fail("Permission was already granted") }, { launched.add(it) })
        flow.open(first, results::add)
        assertEquals(listOf(first), launched)
        assertEquals(listOf<String?>(null), results)
        flow.permissionReturned()
        assertEquals(1, launched.size)
    }

    @Test fun permissionGrantContinuesTheOriginalRequestExactlyOnce() {
        var allowed = false
        var settings = 0
        val launched = mutableListOf<File>()
        val results = mutableListOf<String?>()
        val flow = ApkInstallFlow({ allowed }, { settings++ }, { launched.add(it) })
        flow.open(first, results::add)
        assertEquals(1, settings)
        assertTrue(results.isEmpty())
        assertTrue(launched.isEmpty())
        allowed = true
        flow.permissionReturned()
        flow.permissionReturned()
        assertEquals(listOf(first), launched)
        assertEquals(listOf<String?>(null), results)
    }

    @Test fun permissionDenialReportsAnErrorAndAllowsAnExplicitRetry() {
        var settings = 0
        val results = mutableListOf<String?>()
        val flow = ApkInstallFlow({ false }, { settings++ }, { fail("Permission was denied") })
        flow.open(first, results::add)
        flow.permissionReturned()
        assertTrue(results.single()!!.contains("安装权限未开启"))
        flow.open(first, results::add)
        assertEquals(2, settings)
        assertEquals(1, results.size)
    }

    @Test fun anotherRequestDoesNotReplaceThePendingApk() {
        var allowed = false
        val launched = mutableListOf<File>()
        val firstResults = mutableListOf<String?>()
        val secondResults = mutableListOf<String?>()
        val flow = ApkInstallFlow({ allowed }, {}, { launched.add(it) })
        flow.open(first, firstResults::add)
        flow.open(second, secondResults::add)
        assertTrue(secondResults.single()!!.contains("请先完成"))
        allowed = true
        flow.permissionReturned()
        assertEquals(listOf(first), launched)
        assertEquals(listOf<String?>(null), firstResults)
    }

    @Test fun fileIsRevalidatedAfterThePermissionPage() {
        var allowed = false
        var exists = true
        val results = mutableListOf<String?>()
        val launched = mutableListOf<File>()
        val flow = ApkInstallFlow({ allowed }, {}, {
            check(exists) { "文件已被移动或删除" }
            launched.add(it)
        })
        flow.open(first, results::add)
        exists = false
        allowed = true
        flow.permissionReturned()
        assertEquals(listOf("文件已被移动或删除"), results)
        assertTrue(launched.isEmpty())
    }

    @Test fun unavailableSettingsDoNotLeaveTheFlowBusy() {
        var settings = 0
        val results = mutableListOf<String?>()
        val flow = ApkInstallFlow({ false }, {
            settings++
            error("无法打开授权页面")
        }, { fail("No permission") })
        flow.open(first, results::add)
        flow.open(second, results::add)
        assertEquals(2, settings)
        assertEquals(listOf("无法打开授权页面", "无法打开授权页面"), results)
    }

    @Test fun unavailableInstallerReportsFailureForBothPermissionStates() {
        var allowed = true
        val results = mutableListOf<String?>()
        val flow = ApkInstallFlow({ allowed }, {}, { error("没有可用的应用安装器") })
        flow.open(first, results::add)
        allowed = false
        flow.open(second, results::add)
        allowed = true
        flow.permissionReturned()
        assertEquals(listOf("没有可用的应用安装器", "没有可用的应用安装器"), results)
    }

    @Test fun anUnrelatedReturnCannotTriggerInstallation() {
        var checks = 0
        val flow = ApkInstallFlow({ checks++; true }, { fail("No request") }, { fail("No request") })
        flow.permissionReturned()
        assertEquals(0, checks)
    }
}

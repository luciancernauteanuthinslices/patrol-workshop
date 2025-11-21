package com.example.patrol_challenge

import android.util.Log
import androidx.test.platform.app.InstrumentationRegistry
import androidx.test.uiautomator.UiDevice
import io.qameta.allure.kotlin.Allure
import org.junit.rules.TestRule
import org.junit.runner.Description
import org.junit.runners.model.Statement
import java.io.ByteArrayInputStream
import java.io.File

/**
 * Captures the current window hierarchy when a test fails to aid debugging.
 */
class WindowHierarchyRule : TestRule {
    override fun apply(base: Statement, description: Description): Statement = object : Statement() {
        override fun evaluate() {
            try {
                base.evaluate()
            } catch (t: Throwable) {
                runCatching { captureHierarchy(description) }
                    .onFailure { Log.e(TAG, "Failed to capture window hierarchy", it) }
                throw t
            }
        }
    }

    private fun captureHierarchy(description: Description) {
        val instrumentation = InstrumentationRegistry.getInstrumentation()
        val device = UiDevice.getInstance(instrumentation)
        val cacheDir = instrumentation.targetContext.cacheDir ?: return
        val file = File(cacheDir, "window_hierarchy_${description.methodName}.xml")
        val dumped = runCatching { device.dumpWindowHierarchy(file) }
            .onFailure { Log.w(TAG, "dumpWindowHierarchy threw", it) }
            .getOrDefault(false)
        if (dumped == false) {
            Log.w(TAG, "dumpWindowHierarchy returned false")
            file.delete()
            return
        }

        if (file.exists()) {
            runCatching {
                val bytes = file.readBytes()
                Allure.attachment(
                    name = file.name,
                    content = ByteArrayInputStream(bytes),
                    type = "text/xml",
                    fileExtension = ".xml"
                )
            }.onFailure { Log.w(TAG, "Unable to attach window hierarchy", it) }
            file.delete()
        }
    }

    companion object {
        private const val TAG = "WindowHierarchyRule"
    }
}

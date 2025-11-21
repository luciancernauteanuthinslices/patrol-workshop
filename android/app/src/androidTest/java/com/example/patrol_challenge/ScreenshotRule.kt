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
import java.text.SimpleDateFormat
import java.util.Date
import java.util.Locale

class ScreenshotRule @JvmOverloads constructor(
    private val mode: Mode = Mode.END,
    private val namePrefix: String = "screenshot"
) : TestRule {

    enum class Mode {
        START,
        END,
        FAILURE
    }

    override fun apply(base: Statement, description: Description): Statement = object : Statement() {
        override fun evaluate() {
            var failed = false
            try {
                if (mode == Mode.START) {
                    capture(description, "start")
                }
                base.evaluate()
            } catch (t: Throwable) {
                failed = true
                if (mode == Mode.FAILURE || mode == Mode.END) {
                    capture(description, "failure")
                }
                throw t
            } finally {
                if (!failed && mode == Mode.END) {
                    capture(description, "end")
                }
            }
        }
    }

    private fun capture(description: Description, stage: String) {
        val instrumentation = runCatching { InstrumentationRegistry.getInstrumentation() }
            .onFailure { Log.e(TAG, "Unable to get instrumentation", it) }
            .getOrNull() ?: return

        val device = runCatching { UiDevice.getInstance(instrumentation) }
            .onFailure { Log.e(TAG, "Unable to acquire UiDevice", it) }
            .getOrNull() ?: return

        val cacheDir = instrumentation.targetContext.cacheDir ?: return
        val timestamp = SimpleDateFormat("yyyyMMdd_HHmmss_SSS", Locale.US).format(Date())
        val file = File(cacheDir, "${namePrefix}_${description.methodName}_${stage}_$timestamp.png")

        val success = runCatching { device.takeScreenshot(file) }
            .onFailure { Log.e(TAG, "Screenshot capture failed", it) }
            .getOrDefault(false)

        val bytes = takeIf { success && file.exists() }?.let { runCatching { file.readBytes() }.getOrNull() }
        if (bytes != null) {
            runCatching {
                Allure.attachment(
                    name = file.name,
                    content = ByteArrayInputStream(bytes),
                    type = "image/png",
                    fileExtension = ".png"
                )
            }.onFailure { Log.w(TAG, "Unable to attach screenshot to Allure", it) }
        }
        file.delete()
    }

    companion object {
        private const val TAG = "ScreenshotRule"
    }
}

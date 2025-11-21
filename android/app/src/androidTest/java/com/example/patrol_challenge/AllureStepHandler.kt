package com.example.patrol_challenge;

import android.content.Context
import android.os.Build
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import io.qameta.allure.kotlin.Allure
import io.qameta.allure.kotlin.model.Status
import io.qameta.allure.kotlin.model.StepResult
import java.io.BufferedReader
import java.io.File
import java.io.ByteArrayInputStream
import java.io.InputStreamReader
import java.util.UUID

/**
 * Handles platform channel calls from Dart to log steps in Allure
 */
class AllureStepHandler(private val context: Context) : MethodChannel.MethodCallHandler {
    
    private val stepStack = mutableListOf<String>()

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "startStep" -> {
                val name = call.argument<String>("name") ?: "Unknown step"
                startStep(name)
                result.success(null)
            }
            "stopStep" -> {
                val status = call.argument<String>("status") ?: "passed"
                stopStep(status)
                result.success(null)
            }
            "markTestFailed" -> {
                val testName = call.argument<String>("testName") ?: "Unknown test"
                val error = call.argument<String>("error") ?: "Unknown error"
                captureFailureArtifacts(testName, error)
                result.success(null)
            }
            "attachFile" -> {
                val path = call.argument<String>("path")
                val name = call.argument<String>("name")
                val type = call.argument<String>("type")
                if (path != null && name != null && type != null) {
                    attachFile(path, name, type)
                }
                result.success(null)
            }
            else -> result.notImplemented()
        }
    }

    private fun startStep(name: String) {
        val uuid = UUID.randomUUID().toString()
        stepStack.add(uuid)
        
        Allure.lifecycle.startStep(uuid, StepResult().apply {
            this.name = name
            this.status = Status.PASSED
        })
    }

    private fun stopStep(status: String) {
        if (stepStack.isEmpty()) return
        
        val uuid = stepStack.removeAt(stepStack.size - 1)
        val allureStatus = when (status.lowercase()) {
            "passed" -> Status.PASSED
            "failed" -> Status.FAILED
            "broken" -> Status.BROKEN
            "skipped" -> Status.SKIPPED
            else -> Status.PASSED
        }
        
        Allure.lifecycle.updateStep(uuid) { stepResult ->
            stepResult.status = allureStatus
        }
        Allure.lifecycle.stopStep(uuid)
    }

    private fun captureFailureArtifacts(testName: String, error: String) {
        try {
            // Capture screenshot
            captureScreenshot(testName)
            
            // Capture logcat
            captureLogcat(testName)
            
            // Attach error message
            Allure.lifecycle.addAttachment(
                "Error details",
                ByteArrayInputStream(error.toByteArray()),
                "text/plain",
                ".txt"
            )
        } catch (e: Exception) {
            // Silently fail - don't break test execution
            e.printStackTrace()
        }
    }

    private fun captureScreenshot(testName: String) {
        try {
            val screenshotFile = File(context.cacheDir, "screenshot_${System.currentTimeMillis()}.png")
            
            val process = Runtime.getRuntime().exec(arrayOf(
                "screencap",
                "-p",
                screenshotFile.absolutePath
            ))
            process.waitFor()
            
            if (screenshotFile.exists()) {
                Allure.lifecycle.addAttachment(
                    "Screenshot on failure",
                    ByteArrayInputStream(screenshotFile.readBytes()),
                    "image/png",
                    ".png"
                )
                screenshotFile.delete()
            }
        } catch (e: Exception) {
            e.printStackTrace()
        }
    }

    private fun captureLogcat(testName: String) {
        try {
            val process = Runtime.getRuntime().exec(arrayOf(
                "logcat",
                "-d",
                "-v",
                "time",
                "*:W"
            ))
            
            val reader = BufferedReader(InputStreamReader(process.inputStream))
            val logcat = reader.readText()
            reader.close()
            
            val lines = logcat.lines()
            val lastLines = lines.takeLast(500).joinToString("\n")
            
            Allure.lifecycle.addAttachment(
                "Logcat (last 500 lines)",
                ByteArrayInputStream(lastLines.toByteArray()),
                "text/plain",
                ".txt"
            )
        } catch (e: Exception) {
            e.printStackTrace()
        }
    }

    private fun attachFile(path: String, name: String, type: String) {
        try {
            val file = File(path)
            if (file.exists()) {
                Allure.lifecycle.addAttachment(
                    name,
                    ByteArrayInputStream(file.readBytes()),
                    type,
                    file.extension
                )
            }
        } catch (e: Exception) {
            e.printStackTrace()
        }
    }
}

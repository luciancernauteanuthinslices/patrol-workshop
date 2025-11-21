package your.app.bundle.id //change this to your app's package name

import android.os.Build
import android.util.Log
import androidx.test.platform.app.InstrumentationRegistry
import androidx.test.uiautomator.UiDevice
import io.qameta.allure.kotlin.Allure
import org.junit.rules.TestRule
import org.junit.runner.Description
import org.junit.runners.model.Statement

/**
 * Filters logcat to reduce noise. Clears logs before each test and attaches filtered dump on failure.
 *
 * Defaults: level=I, tags=[Flutter, Patrol, AndroidRuntime]
 */
class FilteredLogcatRule(
    private val minLevel: String = "I",
    private val tags: List<String> = listOf("Flutter", "Patrol", "AndroidRuntime")
) : TestRule {

    override fun apply(base: Statement, description: Description): Statement = object : Statement() {
        override fun evaluate() {
            try {
                clear()
                base.evaluate()
            } catch (t: Throwable) {
                dump(description.displayName)
                throw t
            }
        }
    }

    private fun clear() {
        val dev = try { UiDevice.getInstance(InstrumentationRegistry.getInstrumentation()) } catch (_: Throwable) { null }
            ?: return Unit.also { Log.e(TAG, "UiDevice is unavailable. Clearing logs failed.") }
        dev.executeShellCommandSafely("logcat -c")
    }

    private fun dump(testName: String) {
        val dev = try { UiDevice.getInstance(InstrumentationRegistry.getInstrumentation()) } catch (_: Throwable) { null }
            ?: return Unit.also { Log.e(TAG, "UiDevice is unavailable. Dumping logs failed.") }

        val byPid = captureByPid(dev)
        val output = byPid ?: captureByTags(dev)

        output?.let {
            Allure.attachment(
                name = "logcat ($testName)",
                content = it,
                type = "text/plain",
                fileExtension = ".txt"
            )
        }
    }

    private fun captureByPid(dev: UiDevice): String? {
        val pkg = try {
            InstrumentationRegistry.getInstrumentation().targetContext.packageName
        } catch (_: Throwable) { null }
        if (pkg.isNullOrBlank()) return null
        val pid = dev.executeShellCommandSafely("pidof $pkg")?.trim()?.takeIf { it.isNotEmpty() }
            ?: parsePidFromPs(dev.executeShellCommandSafely("ps | grep $pkg"))
        if (pid.isNullOrBlank()) return null
        // Try pid filtering if supported
        return dev.executeShellCommandSafely("logcat --pid=$pid -d -v time")
    }

    private fun parsePidFromPs(psOut: String?): String? {
        if (psOut.isNullOrBlank()) return null
        return psOut.lineSequence()
            .firstOrNull { it.contains(" $PID_SEP ").not() || it.contains(" ") }
            ?.trim()
            ?.split(Regex("\\s+"))
            ?.getOrNull(1)
    }

    private fun captureByTags(dev: UiDevice): String? {
        val filterSpec = buildFilterSpec()
        return dev.executeShellCommandSafely("logcat -d -v time $filterSpec")
    }

    private fun buildFilterSpec(): String {
        val effectiveLevel = LEVELS.getOrDefault(minLevel.uppercase(), "I")
        val specs = mutableListOf("*:S")
        tags.forEach { tag ->
            val safeTag = tag.replace(" ", "_")
            specs += "$safeTag:$effectiveLevel"
        }
        return specs.joinToString(separator = " ")
    }

    private fun UiDevice.executeShellCommandSafely(cmd: String): String? {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.LOLLIPOP) return null
        return try { executeShellCommand(cmd) } catch (_: Throwable) { null }
    }

    companion object {
        private const val TAG = "FilteredLogcatRule"
        private const val PID_SEP = ":" // dummy, not used
        private val LEVELS = mapOf(
            "V" to "V",
            "D" to "D",
            "I" to "I",
            "W" to "W",
            "E" to "E",
            "F" to "F",
            "S" to "S",
        )
    }
}

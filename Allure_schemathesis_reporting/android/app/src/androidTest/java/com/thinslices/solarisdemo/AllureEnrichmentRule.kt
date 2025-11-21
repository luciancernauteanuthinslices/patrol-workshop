package your.app.bundle.id //change this to your app's package name


import android.os.Build
import io.qameta.allure.kotlin.Allure
import org.junit.rules.TestRule
import org.junit.runner.Description
import org.junit.runners.model.Statement

class AllureEnrichmentRule : TestRule {
    override fun apply(base: Statement, description: Description): Statement = object : Statement() {
        override fun evaluate() {
            try {
                enrich()
                base.evaluate()
            } finally {
                // no-op
            }
        }
    }

    private fun enrich() {
        // Static labels
        Allure.label("suite", "Patrol")
        Allure.label("feature", "Mobile E2E")
        Allure.label("severity", "critical")
        Allure.label("owner", "QA Team")

        // Links from environment
        System.getenv("GIT_SHA")?.takeIf { it.isNotBlank() }?.let { sha ->
            Allure.link("commit", sha)
        }
        System.getenv("TMS_ID")?.takeIf { it.isNotBlank() }?.let { tms ->
            Allure.link("tms", tms)
        }

        // Parameters (per test)
        Allure.parameter("device", "${Build.MANUFACTURER} ${Build.MODEL}")
        Allure.parameter("api", Build.VERSION.SDK_INT.toString())
        Allure.parameter("flavor", System.getenv("FLAVOR") ?: "")
        Allure.parameter("env", System.getenv("APP_ENV") ?: "local")

        // Optional custom attachments from env
        System.getenv("PATROL_CONFIG_JSON")?.takeIf { it.isNotBlank() }?.let { json ->
            Allure.attachment(
                name = "Patrol config",
                content = json,
                type = "application/json",
                fileExtension = ".json"
            )
        }
        System.getenv("FEATURE_FLAGS_TEXT")?.takeIf { it.isNotBlank() }?.let { text ->
            Allure.attachment(
                name = "Feature flags",
                content = text,
                type = "text/plain",
                fileExtension = ".txt"
            )
        }
    }
}

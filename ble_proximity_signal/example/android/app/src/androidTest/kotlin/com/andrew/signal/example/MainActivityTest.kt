package com.andrew.signal.example

import androidx.test.platform.app.InstrumentationRegistry
import org.junit.Test
import org.junit.runner.RunWith
import org.junit.runners.Parameterized
import pl.leancode.patrol.PatrolJUnitRunner

/**
 * Patrol integration test runner for Android.
 *
 * This test class discovers and runs all Patrol tests defined in the
 * integration_test directory. It uses JUnit's Parameterized runner to
 * execute each Dart test file as a separate test case.
 *
 * The PatrolJUnitRunner automatically discovers tests by scanning the
 * integration_test directory for Dart test files.
 */
@RunWith(Parameterized::class)
class MainActivityTest(
    private val dartTestName: String?,
) {
    companion object {
        /**
         * Discovers all Patrol/Dart tests in the integration_test directory.
         *
         * @return List of test configurations, one for each discovered test file
         */
        @JvmStatic
        @Parameterized.Parameters(name = "{0}")
        fun testCases(): Array<Any?>? {
            val instrumentation = InstrumentationRegistry.getInstrumentation() as PatrolJUnitRunner
            // replace "MainActivity.class" with "io.flutter.embedding.android.FlutterActivity.class"
            // if in AndroidManifest.xml in manifest/application/activity you have
            //     android:name="io.flutter.embedding.android.FlutterActivity"
            instrumentation.setUp(MainActivity::class.java)
            instrumentation.waitForPatrolAppService()
            return instrumentation.listDartTests()
        }
    }

    @Test
    fun runDartTest() {
        val instrumentation = InstrumentationRegistry.getInstrumentation() as PatrolJUnitRunner
        instrumentation.runDartTest(dartTestName)
    }
}

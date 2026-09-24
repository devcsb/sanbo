package com.sanbo.sanbo

import org.junit.Assert.assertEquals
import org.junit.Test

class HealthConnectIntentContractTest {
    @Test
    fun availableSdkSelectsManageDataBeforeGenericSettings() {
        assertEquals(
            HealthConnectIntentKind.MANAGE_DATA,
            healthConnectIntentKind(
                sdkAvailable = true,
                manageIntentResolvable = true,
            ),
        )
    }

    @Test
    fun unresolvableManageDataFallsBackToSettingsAction() {
        assertEquals(
            HealthConnectIntentKind.SETTINGS_ACTION,
            healthConnectIntentKind(
                sdkAvailable = true,
                manageIntentResolvable = false,
            ),
        )
    }

    @Test
    fun unavailableProviderReportsFalse() {
        assertEquals(false, shouldReportSettingsOpened(false, false))
    }

    @Test
    fun sdkProvidedSettingsActionWinsOverVersionFallback() {
        assertEquals(
            "android.health.connect.action.HEALTH_HOME_SETTINGS",
            healthConnectSettingsAction(
                sdkAction = "android.health.connect.action.HEALTH_HOME_SETTINGS",
                isAndroid14OrLater = false,
            ),
        )
    }

    @Test
    fun blankSdkActionFallsBackToAndroid14Action() {
        assertEquals(
            "android.health.connect.action.HEALTH_HOME_SETTINGS",
            healthConnectSettingsAction(
                sdkAction = " ",
                isAndroid14OrLater = true,
            ),
        )
    }

    @Test
    fun blankSdkActionFallsBackToAndroid13ProviderAction() {
        assertEquals(
            "androidx.health.ACTION_HEALTH_CONNECT_SETTINGS",
            healthConnectSettingsAction(
                sdkAction = null,
                isAndroid14OrLater = false,
            ),
        )
    }
}

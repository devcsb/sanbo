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
}

package com.sanbo.sanbo

import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Test

class NotificationIntentContractTest {
    @Test
    fun `high speed payload is accepted before it is placed in an intent`() {
        assertEquals("highSpeed", notificationKind("highSpeed"))
    }

    @Test
    fun `unknown kinds are ignored`() {
        assertNull(notificationKind("stationary"))
    }
}

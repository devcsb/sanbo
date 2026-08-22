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

    @Test
    fun `tap payload keeps the session id from the notification intent`() {
        assertEquals("session-1", notificationSessionId("session-1"))
    }

    @Test
    fun `tap delivery waits for the Dart channel readiness handshake`() {
        assertEquals(false, shouldDeliverNotificationTap(channelReady = false, hasChannel = true))
        assertEquals(false, shouldDeliverNotificationTap(channelReady = true, hasChannel = false))
        assertEquals(true, shouldDeliverNotificationTap(channelReady = true, hasChannel = true))
    }
}

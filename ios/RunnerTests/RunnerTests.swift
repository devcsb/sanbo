import XCTest
@testable import Runner

class RunnerTests: XCTestCase {

  func testBufferReturnsOneHighSpeedTapAndClearsIt() {
    let buffer = NotificationTapBuffer()

    buffer.store(kind: "highSpeed", sessionId: "session-1")

    let tap = buffer.take()
    XCTAssertEqual(tap?.kind, "highSpeed")
    XCTAssertEqual(tap?.sessionId, "session-1")
    XCTAssertNil(buffer.take())
  }

  func testBufferIgnoresUnsupportedKinds() {
    let buffer = NotificationTapBuffer()

    buffer.store(kind: "stationary", sessionId: "session-1")

    XCTAssertNil(buffer.take())
  }

  func testBufferIgnoresHighSpeedTapWithoutSessionId() {
    let buffer = NotificationTapBuffer()

    buffer.store(kind: "highSpeed", sessionId: nil)

    XCTAssertNil(buffer.take())
  }

  func testStaleReadinessAcknowledgementCannotPrepareANewerChannel() {
    XCTAssertTrue(shouldAcceptNotificationReadinessAck(currentGeneration: 2, ackGeneration: 2))
    XCTAssertFalse(shouldAcceptNotificationReadinessAck(currentGeneration: 2, ackGeneration: 1))
  }

  func testTapDeliveryRequiresReadyChannel() {
    XCTAssertFalse(shouldDeliverNotificationTap(channelReady: false, hasChannel: true))
    XCTAssertFalse(shouldDeliverNotificationTap(channelReady: true, hasChannel: false))
    XCTAssertTrue(shouldDeliverNotificationTap(channelReady: true, hasChannel: true))
  }

  func testSceneLaunchNotificationPayloadIsAccepted() {
    let tap = notificationTap(from: [
      "kind": "highSpeed",
      "sessionId": "session-from-scene",
    ])

    XCTAssertEqual(tap?.kind, "highSpeed")
    XCTAssertEqual(tap?.sessionId, "session-from-scene")
  }

  func testSceneLaunchNotificationPayloadRejectsUnsupportedValues() {
    XCTAssertNil(notificationTap(from: ["kind": "stationary", "sessionId": "session-1"]))
    XCTAssertNil(notificationTap(from: ["kind": "highSpeed"]))
    XCTAssertNil(notificationTap(from: ["kind": "highSpeed", "sessionId": ""]))
  }

}

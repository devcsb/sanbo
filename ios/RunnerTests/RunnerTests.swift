import XCTest
@testable import Runner

class RunnerTests: XCTestCase {

  func testBufferReturnsOneHighSpeedTapAndClearsIt() {
    let buffer = NotificationTapBuffer()

    buffer.store(kind: "highSpeed")

    XCTAssertEqual(buffer.take(), "highSpeed")
    XCTAssertNil(buffer.take())
  }

  func testBufferIgnoresUnsupportedKinds() {
    let buffer = NotificationTapBuffer()

    buffer.store(kind: "stationary")

    XCTAssertNil(buffer.take())
  }

}

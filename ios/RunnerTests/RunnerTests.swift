import XCTest
import Flutter
import UIKit
@testable import Runner

class RunnerTests: XCTestCase {

  func testBackupSourceMustStayInsideExportRoot() throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: root) }
    let source = root.appendingPathComponent("audit.sanbo")
    try Data("{}".utf8).write(to: source)
    XCTAssertEqual(try validatedBackupExportSource(source: source, fileName: "audit.sanbo",
      exportRoot: root), source.resolvingSymlinksInPath().standardizedFileURL)
    for name in ["", ".", "..", "../audit.sanbo", "a\\b", "a\0b", "wrong.sanbo"] {
      XCTAssertThrowsError(try validatedBackupExportSource(source: source, fileName: name, exportRoot: root))
    }
    XCTAssertThrowsError(try validatedBackupExportSource(source: root,
      fileName: root.lastPathComponent, exportRoot: root))
    XCTAssertThrowsError(try validatedBackupExportSource(source: root.appendingPathComponent("missing.sanbo"),
      fileName: "missing.sanbo", exportRoot: root))
    let outside = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".sanbo")
    try Data("{}".utf8).write(to: outside)
    defer { try? FileManager.default.removeItem(at: outside) }
    let link = root.appendingPathComponent("escape.sanbo")
    try FileManager.default.createSymbolicLink(at: link, withDestinationURL: outside)
    XCTAssertThrowsError(try validatedBackupExportSource(source: outside,
      fileName: outside.lastPathComponent, exportRoot: root))
    XCTAssertThrowsError(try validatedBackupExportSource(source: link,
      fileName: link.lastPathComponent, exportRoot: root))
    let handle = try FileHandle(forWritingTo: source)
    defer { try? handle.close() }
    for size in [UInt64(0), UInt64(50 * 1024 * 1024 + 1)] {
      try handle.truncate(atOffset: size)
      XCTAssertThrowsError(try validatedBackupExportSource(source: source,
        fileName: source.lastPathComponent, exportRoot: root))
    }
  }

  @MainActor func testBackupPickerIgnoresDuplicateAndOlderCallbacks() throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: root) }
    let source = root.appendingPathComponent("audit.sanbo")
    try Data("{}".utf8).write(to: source)
    var pickers: [UIDocumentPickerViewController] = []
    let coordinator = BackupExportCoordinator(exportRoot: root, presentPicker: {
      pickers.append($0); return true
    })
    let call = FlutterMethodCall(methodName: "save", arguments: [
      "sourcePath": source.path, "fileName": source.lastPathComponent,
    ])
    var first: [Any?] = []
    var second: [Any?] = []
    coordinator.handle(call, result: { first.append($0) })
    var busy: Any?
    coordinator.handle(call, result: { busy = $0 })
    XCTAssertEqual((busy as? FlutterError)?.code, "export_busy")
    let destination = root.appendingPathComponent("saved.sanbo")
    coordinator.documentPicker(pickers[0], didPickDocumentsAt: [destination])
    XCTAssertEqual(first.first as? String, destination.absoluteString)
    coordinator.handle(call, result: { second.append($0) })
    coordinator.documentPickerWasCancelled(pickers[0])
    XCTAssertTrue(second.isEmpty)
    coordinator.documentPickerWasCancelled(pickers[1])
    coordinator.documentPickerWasCancelled(pickers[1])
    XCTAssertEqual(first.count, 1)
    XCTAssertEqual(second.count, 1)
    XCTAssertNil(second[0])
    coordinator.close()
  }

  @MainActor func testBackupWithoutPresenterIsUnavailable() throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: root) }
    let source = root.appendingPathComponent("audit.sanbo")
    try Data("{}".utf8).write(to: source)
    let coordinator = BackupExportCoordinator(exportRoot: root, presentPicker: { _ in false })
    var response: Any?
    coordinator.handle(FlutterMethodCall(methodName: "save", arguments: [
      "sourcePath": source.path, "fileName": source.lastPathComponent,
    ]), result: { response = $0 })
    XCTAssertEqual((response as? FlutterError)?.code, "export_unavailable")
    coordinator.close()
  }

  @MainActor func testBackupCloseInterruptsPendingExactlyOnce() throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: root) }
    let source = root.appendingPathComponent("audit.sanbo")
    try Data("{}".utf8).write(to: source)
    var picker: UIDocumentPickerViewController?
    let coordinator = BackupExportCoordinator(exportRoot: root, presentPicker: { picker = $0; return true })
    var replies: [Any?] = []
    coordinator.handle(FlutterMethodCall(methodName: "save", arguments: [
      "sourcePath": source.path, "fileName": source.lastPathComponent,
    ]), result: { replies.append($0) })
    coordinator.close()
    coordinator.close()
    if let picker { coordinator.documentPickerWasCancelled(picker) }
    XCTAssertEqual(replies.count, 1)
    XCTAssertEqual((replies.first ?? nil as Any?) as? FlutterError != nil, true)
    XCTAssertEqual((replies.first.flatMap { $0 } as? FlutterError)?.code, "export_interrupted")
  }

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

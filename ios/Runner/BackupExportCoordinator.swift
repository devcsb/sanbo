import Flutter
import UIKit

enum BackupExportValidationError: Error { case invalidSource }

func validatedBackupExportSource(source: URL, fileName: String, exportRoot: URL) throws -> URL {
  let root = exportRoot.resolvingSymlinksInPath().standardizedFileURL
  let file = source.resolvingSymlinksInPath().standardizedFileURL
  let values = try file.resourceValues(forKeys: [.isRegularFileKey, .fileSizeKey])
  guard !fileName.isEmpty, fileName != ".", fileName != "..",
    !fileName.contains("/"), !fileName.contains("\\"), !fileName.contains("\0"),
    file.path.hasPrefix(root.path + "/"), file.lastPathComponent == fileName,
    values.isRegularFile == true, let size = values.fileSize,
    size > 0, size <= 50 * 1024 * 1024 else {
    throw BackupExportValidationError.invalidSource
  }
  return file
}

@MainActor
final class BackupExportCoordinator: NSObject, UIDocumentPickerDelegate, UIAdaptivePresentationControllerDelegate {
  private struct Pending {
    let picker: UIDocumentPickerViewController
    let result: FlutterResult
  }
  private let exportRoot: URL
  private let presentPicker: (UIDocumentPickerViewController) -> Bool
  private var channel: FlutterMethodChannel?
  private var pending: Pending?
  private var closed = false

  init(exportRoot: URL, presentPicker: @escaping (UIDocumentPickerViewController) -> Bool) {
    self.exportRoot = exportRoot
    self.presentPicker = presentPicker
    super.init()
  }

  func attach(messenger: FlutterBinaryMessenger) {
    let channel = FlutterMethodChannel(name: "sanbo/backup_export", binaryMessenger: messenger)
    self.channel = channel
    channel.setMethodCallHandler { [weak self] call, result in
      guard let self else {
        result(FlutterError(code: "export_unavailable", message: "File export is unavailable.", details: nil))
        return
      }
      self.handle(call, result: result)
    }
  }

  func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    guard call.method == "save" else { result(FlutterMethodNotImplemented); return }
    guard !closed else {
      result(exportError("export_unavailable")); return
    }
    guard pending == nil else {
      result(exportError("export_busy")); return
    }
    guard let args = call.arguments as? [String: Any],
      let path = args["sourcePath"] as? String,
      let name = args["fileName"] as? String else {
      result(exportError("invalid_arguments")); return
    }
    let source: URL
    do {
      source = try validatedBackupExportSource(source: URL(fileURLWithPath: path),
        fileName: name, exportRoot: exportRoot)
    } catch {
      result(exportError("invalid_arguments")); return
    }
    let picker = UIDocumentPickerViewController(forExporting: [source], asCopy: true)
    picker.delegate = self
    pending = Pending(picker: picker, result: result)
    guard presentPicker(picker) else {
      finish(picker, value: exportError("export_unavailable")); return
    }
    picker.presentationController?.delegate = self
  }

  func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) {
    guard !closed else {
      finish(controller, value: exportError("export_interrupted")); return
    }
    guard let destination = urls.first else {
      finish(controller, value: exportError("export_failed")); return
    }
    finish(controller, value: destination.absoluteString)
  }

  func documentPickerWasCancelled(_ controller: UIDocumentPickerViewController) {
    finish(controller, value: closed ? exportError("export_interrupted") : nil)
  }

  func presentationControllerDidDismiss(_ presentationController: UIPresentationController) {
    guard let operation = pending,
      operation.picker.presentationController === presentationController else { return }
    finish(operation.picker, value: closed ? exportError("export_interrupted") : nil)
  }

  private func finish(_ picker: UIDocumentPickerViewController, value: Any?) {
    guard let operation = pending, operation.picker === picker else { return }
    pending = nil
    picker.delegate = nil
    picker.presentationController?.delegate = nil
    operation.result(value)
  }

  private func exportError(_ code: String) -> FlutterError {
    FlutterError(code: code, message: "File export did not complete.", details: nil)
  }

  func close() {
    guard !closed else { return }
    closed = true
    channel?.setMethodCallHandler(nil)
    channel = nil
    guard let operation = pending else { return }
    // Keep the coordinator and source alive until dismissal finishes.
    if operation.picker.presentingViewController != nil {
      operation.picker.dismiss(animated: false) {
        self.finish(operation.picker, value: self.exportError("export_interrupted"))
      }
    } else {
      finish(operation.picker, value: exportError("export_interrupted"))
    }
  }
}

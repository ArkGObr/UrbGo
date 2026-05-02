import Flutter
import UIKit
import UniformTypeIdentifiers

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate, UIDocumentPickerDelegate {
  private let documentPickerChannel = "com.urbgo.app/document_picker"
  private var pendingDocumentResult: FlutterResult?

  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    if let controller = window?.rootViewController as? FlutterViewController {
      let channel = FlutterMethodChannel(
        name: documentPickerChannel,
        binaryMessenger: controller.binaryMessenger
      )

      channel.setMethodCallHandler { [weak self] call, result in
        guard let self else { return }

        if call.method == "pickPdf" {
          self.openPdfPicker(result: result)
        } else {
          result(FlutterMethodNotImplemented)
        }
      }
    }

    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
    GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)
  }

  private func openPdfPicker(result: @escaping FlutterResult) {
    guard pendingDocumentResult == nil else {
      result(
        FlutterError(
          code: "PICK_IN_PROGRESS",
          message: "Já existe uma seleção de PDF em andamento.",
          details: nil
        )
      )
      return
    }

    pendingDocumentResult = result
    let picker = UIDocumentPickerViewController(forOpeningContentTypes: [UTType.pdf])
    picker.delegate = self
    picker.allowsMultipleSelection = false
    picker.modalPresentationStyle = .formSheet
    window?.rootViewController?.present(picker, animated: true)
  }

  func documentPickerWasCancelled(_ controller: UIDocumentPickerViewController) {
    pendingDocumentResult?(nil)
    pendingDocumentResult = nil
  }

  func documentPicker(
    _ controller: UIDocumentPickerViewController,
    didPickDocumentsAt urls: [URL]
  ) {
    guard let url = urls.first else {
      pendingDocumentResult?(
        FlutterError(
          code: "PICK_FAILED",
          message: "Nenhum arquivo selecionado.",
          details: nil
        )
      )
      pendingDocumentResult = nil
      return
    }

    do {
      let destination = try copyPdfToTemporaryDirectory(from: url)
      pendingDocumentResult?(destination.path)
    } catch {
      pendingDocumentResult?(
        FlutterError(
          code: "PICK_FAILED",
          message: error.localizedDescription,
          details: nil
        )
      )
    }

    pendingDocumentResult = nil
  }

  private func copyPdfToTemporaryDirectory(from url: URL) throws -> URL {
    let tempDir = FileManager.default.temporaryDirectory
    let fileName = url.lastPathComponent.isEmpty
      ? "documento-\(Int(Date().timeIntervalSince1970)).pdf"
      : url.lastPathComponent
    let destination = tempDir.appendingPathComponent(fileName)

    let shouldStopAccessing = url.startAccessingSecurityScopedResource()
    defer {
      if shouldStopAccessing {
        url.stopAccessingSecurityScopedResource()
      }
    }

    if FileManager.default.fileExists(atPath: destination.path) {
      try FileManager.default.removeItem(at: destination)
    }

    try FileManager.default.copyItem(at: url, to: destination)
    return destination
  }
}

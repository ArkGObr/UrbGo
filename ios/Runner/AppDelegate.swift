import Flutter
import QuickLook
import UIKit
import UniformTypeIdentifiers

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate, UIDocumentPickerDelegate, QLPreviewControllerDataSource {
  private let documentPickerChannel = "com.arkgo.app/document_picker"
  private let documentOpenerChannel = "com.arkgo.app/document_opener"
  private var pendingDocumentResult: FlutterResult?
  private var previewDocumentUrl: URL?

  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    if let controller = window?.rootViewController as? FlutterViewController {
      let channel = FlutterMethodChannel(
        name: documentPickerChannel,
        binaryMessenger: controller.binaryMessenger
      )
      let openerChannel = FlutterMethodChannel(
        name: documentOpenerChannel,
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

      openerChannel.setMethodCallHandler { [weak self] call, result in
        guard let self else { return }

        if call.method == "openDocument" {
          guard
            let args = call.arguments as? [String: Any],
            let path = args["path"] as? String,
            !path.isEmpty
          else {
            result(
              FlutterError(
                code: "INVALID_ARGUMENT",
                message: "Path missing",
                details: nil
              )
            )
            return
          }

          self.openDocument(atPath: path, result: result)
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

  private func openDocument(atPath path: String, result: FlutterResult) {
    let url = URL(fileURLWithPath: path)
    guard FileManager.default.fileExists(atPath: url.path) else {
      result(
        FlutterError(
          code: "OPEN_DOCUMENT_FAILED",
          message: "Arquivo não encontrado para abertura.",
          details: nil
        )
      )
      return
    }

    previewDocumentUrl = url
    let previewController = QLPreviewController()
    previewController.dataSource = self

    guard let root = window?.rootViewController else {
      result(
        FlutterError(
          code: "OPEN_DOCUMENT_FAILED",
          message: "Não foi possível abrir a visualização do documento.",
          details: nil
        )
      )
      return
    }

    root.present(previewController, animated: true)
    result(nil)
  }

  func numberOfPreviewItems(in controller: QLPreviewController) -> Int {
    previewDocumentUrl == nil ? 0 : 1
  }

  func previewController(
    _ controller: QLPreviewController,
    previewItemAt index: Int
  ) -> QLPreviewItem {
    previewDocumentUrl! as NSURL
  }
}

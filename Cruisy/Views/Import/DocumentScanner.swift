import SwiftUI
import VisionKit

/// Lo scanner di documenti di sistema: ritaglia, raddrizza e pulisce da solo.
///
/// Vale la pena passarci invece di scattare una foto normale: l'OCR su una pagina
/// raddrizzata sbaglia molto meno, e qui un carattere sbagliato è un orario sbagliato.
struct DocumentScanner: UIViewControllerRepresentable {
    let onFinish: ([CGImage]) -> Void
    @Environment(\.dismiss) private var dismiss

    func makeUIViewController(context: Context) -> VNDocumentCameraViewController {
        let controller = VNDocumentCameraViewController()
        controller.delegate = context.coordinator
        return controller
    }

    func updateUIViewController(_ controller: VNDocumentCameraViewController, context: Context) {}

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    /// `@preconcurrency`: VisionKit chiama il delegato sul thread principale, e
    /// la conformanza lo dichiara, così i metodi restano isolati come la vista.
    @MainActor
    final class Coordinator: NSObject, @preconcurrency VNDocumentCameraViewControllerDelegate {
        private let parent: DocumentScanner
        init(_ parent: DocumentScanner) { self.parent = parent }

        func documentCameraViewController(_ controller: VNDocumentCameraViewController,
                                          didFinishWith scan: VNDocumentCameraScan) {
            let pages = (0..<scan.pageCount).compactMap { scan.imageOfPage(at: $0).cgImage }
            parent.onFinish(pages)
            parent.dismiss()
        }

        func documentCameraViewControllerDidCancel(_ controller: VNDocumentCameraViewController) {
            parent.dismiss()
        }

        func documentCameraViewController(_ controller: VNDocumentCameraViewController,
                                          didFailWithError error: Error) {
            parent.onFinish([])
            parent.dismiss()
        }
    }
}

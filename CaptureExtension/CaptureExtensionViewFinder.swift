import LockedCameraCapture
import SwiftUI
import UIKit
import UniformTypeIdentifiers

struct CaptureExtensionViewFinder: UIViewControllerRepresentable {
    let session: LockedCameraCaptureSession

    func makeUIViewController(context: Context) -> UIImagePickerController {
        let picker = UIImagePickerController()
        picker.sourceType = .camera
        picker.mediaTypes = [UTType.image.identifier, UTType.movie.identifier]
        picker.cameraDevice = .rear
        return picker
    }

    func updateUIViewController(_ uiViewController: UIImagePickerController, context: Context) {}
}

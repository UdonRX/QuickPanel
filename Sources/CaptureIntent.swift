import AppIntents
import Foundation

extension Notification.Name {
    static let cameraControlDidActivate = Notification.Name("cameraControlDidActivate")
}

struct CaptureIntent: CameraCaptureIntent {
    static let title: LocalizedStringResource = "QuickPanel Camera"
    static let description = IntentDescription("カメラコントロールからQuickPanelのカメラを起動します。")
    static var isDiscoverable: Bool = false

    @MainActor
    func perform() async throws -> some IntentResult {
        NotificationCenter.default.post(name: .cameraControlDidActivate, object: nil)
        return .result()
    }
}

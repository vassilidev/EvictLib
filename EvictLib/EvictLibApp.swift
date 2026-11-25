import SwiftUI
import Photos

@main
struct EvictLibApp: App {
    @State private var status = PHPhotoLibrary.authorizationStatus(for: .readWrite)
    @State private var library = Library.shared
    @Environment(\.scenePhase) private var phase

    var body: some Scene {
        WindowGroup {
            Group {
                switch status {
                case .authorized:
                    RootView().environment(library)
                case .notDetermined:
                    ProgressView().task { status = await PHPhotoLibrary.requestAuthorization(for: .readWrite) }
                default:    // .limited, .denied, .restricted
                    ContentUnavailableView {
                        Label("Full Access Required", systemImage: "photo.badge.exclamationmark")
                    } description: {
                        Text("EvictLib needs to see your whole library to measure sizes and never delete blindly.\nSettings › EvictLib › Photos › Full Access.")
                    } actions: {
                        Button("Open Settings") { UIApplication.shared.open(URL(string: UIApplication.openSettingsURLString)!) }
                    }
                }
            }
            .onChange(of: phase) {
                if phase == .active { status = PHPhotoLibrary.authorizationStatus(for: .readWrite) }
                else { library.persist() }
            }
        }
    }
}

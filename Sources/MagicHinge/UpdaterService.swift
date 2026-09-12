import Combine
import Sparkle

@MainActor
final class UpdaterService: ObservableObject {
    private let controller: SPUStandardUpdaterController
    @Published private(set) var canCheckForUpdates = false
    @Published var automaticallyChecksForUpdates: Bool {
        didSet { controller.updater.automaticallyChecksForUpdates = automaticallyChecksForUpdates }
    }
    private var observation: AnyCancellable?
    init() {
        controller = SPUStandardUpdaterController(startingUpdater: false, updaterDelegate: nil, userDriverDelegate: nil)
        automaticallyChecksForUpdates = controller.updater.automaticallyChecksForUpdates
        observation = controller.updater.publisher(for: \.canCheckForUpdates).receive(on: RunLoop.main)
            .sink { [weak self] in self?.canCheckForUpdates = $0 }
        // Development builds have no production feed/key and must not query the public update service.
        if Bundle.main.object(forInfoDictionaryKey: "SUPublicEDKey") as? String != nil {
            controller.startUpdater()
        }
    }
    func checkForUpdates() { controller.checkForUpdates(nil) }
}

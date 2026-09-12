import Foundation
import Combine

@MainActor
final class OnboardingCoordinator: ObservableObject {
    enum Step: Int, CaseIterable { case welcome, screenRecording, ready }
    @Published private(set) var step: Step
    @Published var isPresented: Bool
    private let defaults: UserDefaults
    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        step = Step(rawValue: defaults.integer(forKey: "onboarding.step")) ?? .welcome
        isPresented = !defaults.bool(forKey: "onboarding.complete")
    }
    func go(to step: Step) { self.step = step; defaults.set(step.rawValue, forKey: "onboarding.step") }
    func finish() { defaults.set(true, forKey: "onboarding.complete"); isPresented = false }
    func reopen() { go(to: .welcome); isPresented = true }
}

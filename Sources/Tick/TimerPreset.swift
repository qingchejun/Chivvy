import Foundation

struct TimerPreset: Identifiable, Codable, Equatable {
    var id: UUID
    var label: String
    var minutes: Int

    init(id: UUID = UUID(), label: String, minutes: Int) {
        self.id = id
        self.label = label
        self.minutes = minutes
    }

    static let builtIn: [TimerPreset] = [
        TimerPreset(label: "5 分钟", minutes: 5),
        TimerPreset(label: "10 分钟", minutes: 10),
        TimerPreset(label: "15 分钟", minutes: 15),
        TimerPreset(label: "25 分钟", minutes: 25),
    ]

    static let maxCount = 5
}

@MainActor
final class PresetStore: ObservableObject {
    static let shared = PresetStore()

    @Published var presets: [TimerPreset] {
        didSet { save() }
    }

    private let key = "customPresets"

    private init() {
        if let data = UserDefaults.standard.data(forKey: key),
           let saved = try? JSONDecoder().decode([TimerPreset].self, from: data) {
            presets = saved
        } else {
            presets = TimerPreset.builtIn
        }
    }

    func reset() {
        presets = TimerPreset.builtIn
    }

    private func save() {
        if let data = try? JSONEncoder().encode(presets) {
            UserDefaults.standard.set(data, forKey: key)
        }
    }
}

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

    /// Auto-generated labels ("5 分钟" / "5 min") follow the UI language; names the user typed are kept as is
    var displayLabel: String {
        isDefaultLabel ? Self.defaultLabel(minutes) : label
    }

    /// Compact form for tight grids (menu bar): "10 分" / "10m"
    var shortLabel: String {
        isDefaultLabel ? L("\(minutes) 分", "\(minutes)m") : label
    }

    private var isDefaultLabel: Bool {
        label == "\(minutes) 分钟" || label == "\(minutes) min"
    }

    static func defaultLabel(_ minutes: Int) -> String {
        L("\(minutes) 分钟", "\(minutes) min")
    }

    static var builtIn: [TimerPreset] {
        [5, 10, 15, 25].map { TimerPreset(label: defaultLabel($0), minutes: $0) }
    }

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

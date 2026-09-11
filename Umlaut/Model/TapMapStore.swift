import Foundation
import KeyboardCore

/// Observable view of the tap map shared with the keyboard extension.
@MainActor
final class TapMapStore: ObservableObject {

    struct LayerInfo: Identifiable, Equatable {
        /// Horizontal key pitch in points – identifies the keyboard width the layer was learned on.
        let pitchX: CGFloat
        /// The letters in reading order ("qwertz…"), identifies the layout.
        let arrangement: String
        let layer: TapMap.Layer
        var id: String { "\(pitchX)|\(arrangement)" }
    }

    @Published private(set) var layers: [LayerInfo] = []

    private let map = TapMap.standard

    init() {
        reload()
    }

    /// The layer with the most taps behind it – what the user types on most of the time.
    var primary: LayerInfo? {
        layers.max { $0.layer.sampleCount < $1.layer.sampleCount }
    }

    var totalSamples: Int { layers.reduce(0) { $0 + $1.layer.sampleCount } }

    func reload() {
        map.reloadIfChanged()      // the keyboard may have learned meanwhile
        layers = map.layers.map { LayerInfo(pitchX: $0.pitchX, arrangement: $0.arrangement, layer: $0.layer) }
    }

    func reset() {
        map.removeAll()
        map.saveNow()
        reload()
    }

    /// Human-readable name for a layer: the narrowest keyboard is portrait, the widest landscape,
    /// with the layout's first letters appended when several layouts were learned.
    func title(for info: LayerInfo) -> String {
        let pitches = Set(layers.map(\.pitchX)).sorted()
        var title: String
        if pitches.count <= 1 { title = "Tastatur" }
        else if info.pitchX == pitches.first { title = "Hochformat" }
        else if info.pitchX == pitches.last { title = "Querformat" }
        else { title = "\(Int(info.pitchX)) pt" }
        if Set(layers.map(\.arrangement)).count > 1 {
            title += " · " + info.arrangement.prefix(6).uppercased()
        }
        return title
    }
}

import Core
import Foundation
import Observation

/// A device-local ring buffer of recently logged foods, surfaced in the search
/// sheet so repetitive eaters (the app's core audience — carnivore/low-carb diets
/// repeat meals daily) can re-log without searching.
///
/// Only product-backed logs (search / barcode / custom catalogue) are recorded:
/// they carry per-100 g nutrition and a `source`, so a re-log keeps honest
/// provenance. Free-text entries are not recorded — synthesising a provenance for
/// them would mislabel the numbers (NUTRITION_DATA.md posture).
@MainActor
@Observable
public final class RecentFoodsStore {

    public struct RecentFood: Codable, Identifiable, Sendable {
        public var id: String { "\(source.rawValue)|\(code)|\(name)|\(brand ?? "")" }

        public let code: String
        public let name: String
        public let brand: String?
        public let source: FoodSource
        public let energyKcal100g: Double?
        public let carbs100g: Double?
        public let protein100g: Double?
        public let fat100g: Double?
        public let saturatedFat100g: Double?
        public let sodium100g: Double?
        public let ingredients: String?
        public var lastQuantityG: Double
        public var lastUsedAt: Date

        public func asFoodItem() -> FoodItem {
            FoodItem(
                code: code,
                name: name,
                brand: brand,
                source: source,
                energyKcal100g: energyKcal100g,
                carbs100g: carbs100g,
                protein100g: protein100g,
                fat100g: fat100g,
                saturatedFat100g: saturatedFat100g,
                sodium100g: sodium100g,
                ingredients: ingredients
            )
        }
    }

    public private(set) var items: [RecentFood] = []

    private static let capacity = 20
    private static let key = "food.recents"

    public init() {
        if let data = UserDefaults.standard.data(forKey: Self.key),
           let decoded = try? JSONDecoder().decode([RecentFood].self, from: data) {
            items = decoded
        }
    }

    /// Records a logged product at the head of the list, deduplicating on the
    /// product identity and capping the buffer.
    public func record(item: FoodItem, quantityG: Double) {
        let recent = RecentFood(
            code: item.code,
            name: item.name,
            brand: item.brand,
            source: item.source,
            energyKcal100g: item.energyKcal100g,
            carbs100g: item.carbs100g,
            protein100g: item.protein100g,
            fat100g: item.fat100g,
            saturatedFat100g: item.saturatedFat100g,
            sodium100g: item.sodium100g,
            ingredients: item.ingredients,
            lastQuantityG: quantityG,
            lastUsedAt: .now
        )
        items.removeAll { $0.id == recent.id }
        items.insert(recent, at: 0)
        if items.count > Self.capacity {
            items.removeLast(items.count - Self.capacity)
        }
        persist()
    }

    private func persist() {
        if let data = try? JSONEncoder().encode(items) {
            UserDefaults.standard.set(data, forKey: Self.key)
        }
    }
}

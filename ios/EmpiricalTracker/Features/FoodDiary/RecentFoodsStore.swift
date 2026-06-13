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
        /// How many times this product has been logged. Drives the "most used"
        /// quick-add ordering. Defaults to 1 when decoding buffers persisted
        /// before this field existed (see `init(from:)`).
        public var useCount: Int

        public init(
            code: String,
            name: String,
            brand: String?,
            source: FoodSource,
            energyKcal100g: Double?,
            carbs100g: Double?,
            protein100g: Double?,
            fat100g: Double?,
            saturatedFat100g: Double?,
            sodium100g: Double?,
            ingredients: String?,
            lastQuantityG: Double,
            lastUsedAt: Date,
            useCount: Int
        ) {
            self.code = code
            self.name = name
            self.brand = brand
            self.source = source
            self.energyKcal100g = energyKcal100g
            self.carbs100g = carbs100g
            self.protein100g = protein100g
            self.fat100g = fat100g
            self.saturatedFat100g = saturatedFat100g
            self.sodium100g = sodium100g
            self.ingredients = ingredients
            self.lastQuantityG = lastQuantityG
            self.lastUsedAt = lastUsedAt
            self.useCount = useCount
        }

        // Backward-compatible decode: `useCount` was added later, so buffers
        // persisted before this release won't carry it — default those to 1.
        public init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            code = try c.decode(String.self, forKey: .code)
            name = try c.decode(String.self, forKey: .name)
            brand = try c.decodeIfPresent(String.self, forKey: .brand)
            source = try c.decode(FoodSource.self, forKey: .source)
            energyKcal100g = try c.decodeIfPresent(Double.self, forKey: .energyKcal100g)
            carbs100g = try c.decodeIfPresent(Double.self, forKey: .carbs100g)
            protein100g = try c.decodeIfPresent(Double.self, forKey: .protein100g)
            fat100g = try c.decodeIfPresent(Double.self, forKey: .fat100g)
            saturatedFat100g = try c.decodeIfPresent(Double.self, forKey: .saturatedFat100g)
            sodium100g = try c.decodeIfPresent(Double.self, forKey: .sodium100g)
            ingredients = try c.decodeIfPresent(String.self, forKey: .ingredients)
            lastQuantityG = try c.decode(Double.self, forKey: .lastQuantityG)
            lastUsedAt = try c.decode(Date.self, forKey: .lastUsedAt)
            useCount = try c.decodeIfPresent(Int.self, forKey: .useCount) ?? 1
        }

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

    /// The most-used products, surfaced as one-tap "quick add" defaults so
    /// repetitive eaters skip the search entirely. Ordered by use count, then
    /// recency as a tiebreaker.
    public var topUsed: [RecentFood] {
        items
            .sorted { ($0.useCount, $0.lastUsedAt) > ($1.useCount, $1.lastUsedAt) }
            .prefix(Self.topUsedLimit)
            .map { $0 }
    }

    private static let capacity = 20
    private static let topUsedLimit = 5
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
        // Carry the running use count forward from any existing entry so the
        // "most used" ordering reflects total logs, not just the latest.
        let previousCount = items.first { $0.id == identity(of: item) }?.useCount ?? 0
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
            lastUsedAt: .now,
            useCount: previousCount + 1
        )
        items.removeAll { $0.id == recent.id }
        items.insert(recent, at: 0)
        if items.count > Self.capacity {
            items.removeLast(items.count - Self.capacity)
        }
        persist()
    }

    /// The `RecentFood.id` a freshly logged item would map to — used to find an
    /// existing entry so its use count can be carried forward.
    private func identity(of item: FoodItem) -> String {
        "\(item.source.rawValue)|\(item.code)|\(item.name)|\(item.brand ?? "")"
    }

    private func persist() {
        if let data = try? JSONEncoder().encode(items) {
            UserDefaults.standard.set(data, forKey: Self.key)
        }
    }
}

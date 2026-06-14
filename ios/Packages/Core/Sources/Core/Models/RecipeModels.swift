import Foundation

// MARK: - Recipe

/// A single recipe in the browsable catalogue. Mirrors the `recipes` table and
/// every `/recipes` route in `api/app/recipes/router.py`.
///
/// `ingredients` and `instructions` are ordered free-text lists, presented as a
/// checklist and numbered steps respectively. The macro fields are the author's
/// per-serving estimates shown in the "Estimated nutrition" card. `isFavorite`
/// and `isNew` are **derived server-side** (the user's star, and "created within
/// the last 14 days") — they are read-only here.
public struct Recipe: Codable, Identifiable, Sendable, Hashable {
    public let id: String
    public let title: String
    public let category: String
    public let imageUrl: String?
    public let servingSize: String?
    public let caloriesKcal: Double?
    public let proteinG: Double?
    public let fatG: Double?
    public let carbsG: Double?
    public let ingredients: [String]
    public let instructions: [String]
    /// The orange "Recipe Fact" blurb shown above the instructions.
    public let fact: String?
    public let isPublic: Bool
    public let isPremium: Bool
    /// The user has starred this recipe.
    public let isFavorite: Bool
    /// Created within the New! window — drives the "New!" badge on cards.
    public let isNew: Bool
    public let createdAt: Date?

    public init(
        id: String,
        title: String,
        category: String,
        imageUrl: String? = nil,
        servingSize: String? = nil,
        caloriesKcal: Double? = nil,
        proteinG: Double? = nil,
        fatG: Double? = nil,
        carbsG: Double? = nil,
        ingredients: [String] = [],
        instructions: [String] = [],
        fact: String? = nil,
        isPublic: Bool = false,
        isPremium: Bool = false,
        isFavorite: Bool = false,
        isNew: Bool = false,
        createdAt: Date? = nil
    ) {
        self.id = id
        self.title = title
        self.category = category
        self.imageUrl = imageUrl
        self.servingSize = servingSize
        self.caloriesKcal = caloriesKcal
        self.proteinG = proteinG
        self.fatG = fatG
        self.carbsG = carbsG
        self.ingredients = ingredients
        self.instructions = instructions
        self.fact = fact
        self.isPublic = isPublic
        self.isPremium = isPremium
        self.isFavorite = isFavorite
        self.isNew = isNew
        self.createdAt = createdAt
    }

    private enum CodingKeys: String, CodingKey {
        case id, title, category
        case imageUrl, servingSize
        case caloriesKcal, proteinG, fatG, carbsG
        case ingredients, instructions, fact
        case isPublic, isPremium, isFavorite, isNew
        case createdAt
    }

    // Tolerant decode: flags and lists may be absent on partial payloads.
    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id           = try c.decode(String.self, forKey: .id)
        title        = try c.decode(String.self, forKey: .title)
        category     = try c.decode(String.self, forKey: .category)
        imageUrl     = try c.decodeIfPresent(String.self, forKey: .imageUrl)
        servingSize  = try c.decodeIfPresent(String.self, forKey: .servingSize)
        caloriesKcal = try c.decodeIfPresent(Double.self, forKey: .caloriesKcal)
        proteinG     = try c.decodeIfPresent(Double.self, forKey: .proteinG)
        fatG         = try c.decodeIfPresent(Double.self, forKey: .fatG)
        carbsG       = try c.decodeIfPresent(Double.self, forKey: .carbsG)
        ingredients  = try c.decodeIfPresent([String].self, forKey: .ingredients) ?? []
        instructions = try c.decodeIfPresent([String].self, forKey: .instructions) ?? []
        fact         = try c.decodeIfPresent(String.self, forKey: .fact)
        isPublic     = try c.decodeIfPresent(Bool.self, forKey: .isPublic) ?? false
        isPremium    = try c.decodeIfPresent(Bool.self, forKey: .isPremium) ?? false
        isFavorite   = try c.decodeIfPresent(Bool.self, forKey: .isFavorite) ?? false
        isNew        = try c.decodeIfPresent(Bool.self, forKey: .isNew) ?? false
        createdAt    = try c.decodeIfPresent(Date.self, forKey: .createdAt)
    }
}

// MARK: - Convenience

public extension Recipe {
    /// A `Recipe` with `isFavorite` flipped, for optimistic UI updates while the
    /// `PUT /recipes/{id}/favorite` call is in flight.
    func togglingFavorite() -> Recipe {
        Recipe(
            id: id, title: title, category: category, imageUrl: imageUrl,
            servingSize: servingSize, caloriesKcal: caloriesKcal, proteinG: proteinG,
            fatG: fatG, carbsG: carbsG, ingredients: ingredients,
            instructions: instructions, fact: fact, isPublic: isPublic,
            isPremium: isPremium, isFavorite: !isFavorite, isNew: isNew,
            createdAt: createdAt
        )
    }
}

// MARK: - RecipePayload (POST / PUT body)

/// Body for creating or updating a recipe. The server derives `isFavorite` /
/// `isNew`, so they are intentionally absent here.
///
/// Also `Decodable`: `POST /recipes/import-url` returns a preview in this same
/// shape, which the import flow decodes directly and hands to `RecipeFormView`.
public struct RecipePayload: Codable, Sendable {
    public let title: String
    public let category: String
    public let imageUrl: String?
    public let servingSize: String?
    public let caloriesKcal: Double?
    public let proteinG: Double?
    public let fatG: Double?
    public let carbsG: Double?
    public let ingredients: [String]
    public let instructions: [String]
    public let fact: String?
    public let isPublic: Bool
    public let isPremium: Bool

    public init(
        title: String,
        category: String,
        imageUrl: String? = nil,
        servingSize: String? = nil,
        caloriesKcal: Double? = nil,
        proteinG: Double? = nil,
        fatG: Double? = nil,
        carbsG: Double? = nil,
        ingredients: [String] = [],
        instructions: [String] = [],
        fact: String? = nil,
        isPublic: Bool = false,
        isPremium: Bool = false
    ) {
        self.title = title
        self.category = category
        self.imageUrl = imageUrl
        self.servingSize = servingSize
        self.caloriesKcal = caloriesKcal
        self.proteinG = proteinG
        self.fatG = fatG
        self.carbsG = carbsG
        self.ingredients = ingredients
        self.instructions = instructions
        self.fact = fact
        self.isPublic = isPublic
        self.isPremium = isPremium
    }
}

// MARK: - RecipeFavoritePayload (PUT body)

public struct RecipeFavoritePayload: Encodable, Sendable {
    public let favorite: Bool
    public init(favorite: Bool) { self.favorite = favorite }
}

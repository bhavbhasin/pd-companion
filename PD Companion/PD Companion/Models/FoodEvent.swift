import Foundation
import SwiftData

@Model
final class FoodEvent {
    var id: UUID
    var timestamp: Date
    var type: FoodType
    var attributes: [FoodAttribute]
    var notes: String?

    init(
        timestamp: Date = .now,
        type: FoodType,
        attributes: [FoodAttribute] = [],
        notes: String? = nil
    ) {
        self.id = UUID()
        self.timestamp = timestamp
        self.type = type
        self.attributes = attributes
        self.notes = notes
    }
}

enum FoodType: String, Codable, CaseIterable {
    case drink
    case mealSnack

    var displayName: String {
        switch self {
        case .drink:    return "Drink"
        case .mealSnack: return "Meal/Snack"
        }
    }

    var symbolName: String {
        switch self {
        case .drink:    return "cup.and.saucer.fill"
        case .mealSnack: return "fork.knife"
        }
    }

    var timelineColor: String {
        switch self {
        case .drink:    return "teal"
        case .mealSnack: return "brown"
        }
    }
}

enum FoodAttribute: String, Codable, CaseIterable {
    case caffeine, protein, sugar, fiber, fat

    var displayName: String {
        switch self {
        case .caffeine: return "Caffeine"
        case .protein:  return "Protein"
        case .sugar:    return "Sugar"
        case .fiber:    return "Fiber"
        case .fat:      return "Fat"
        }
    }
}

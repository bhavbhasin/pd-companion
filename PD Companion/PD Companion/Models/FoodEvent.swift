import Foundation
import SwiftData

@Model
final class FoodEvent {
    var id: UUID
    var timestamp: Date
    var userDescription: String?
    var attributes: [FoodAttribute]  // ML-determined; empty until analysis runs
    var type: FoodType               // kept for schema compat; always .mealSnack on new entries
    var notes: String?

    init(
        timestamp: Date = .now,
        userDescription: String? = nil,
        attributes: [FoodAttribute] = [],
        notes: String? = nil
    ) {
        self.id = UUID()
        self.timestamp = timestamp
        self.userDescription = userDescription
        self.attributes = attributes
        self.type = .mealSnack
        self.notes = notes
    }
}

enum FoodType: String, Codable, CaseIterable {
    case drink
    case mealSnack

    var displayName: String {
        switch self {
        case .drink:     return "Drink"
        case .mealSnack: return "Meal/Snack"
        }
    }

    var symbolName: String {
        switch self {
        case .drink:     return "cup.and.saucer.fill"
        case .mealSnack: return "fork.knife"
        }
    }

    var timelineColor: String {
        switch self {
        case .drink:     return "teal"
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

    static func detect(in description: String) -> [FoodAttribute] {
        let text = description.lowercased()
        var result: [FoodAttribute] = []

        let caffeineWords = ["coffee", "espresso", "latte", "cappuccino", "americano", "cold brew",
                             "matcha", "green tea", "black tea", "energy drink", "caffeine",
                             "cola", "coke", "red bull", "monster", "chai"]
        if caffeineWords.contains(where: { text.contains($0) }) { result.append(.caffeine) }

        let proteinWords = ["chicken", "beef", "steak", "fish", "salmon", "tuna", "egg", "tofu",
                            "soy", "turkey", "pork", "lamb", "meat", "protein", "yogurt", "paneer",
                            "dal", "daal", "dahl", "dhal", "lentil", "bean", "shrimp", "prawn",
                            "cottage cheese", "tempeh", "seitan", "edamame", "whey", "chickpea",
                            "chole", "rajma", "mutton", "keema", "sardine", "mackerel", "cod",
                            "halibut", "tilapia", "crab", "lobster", "scallop", "clam", "mussel"]
        if proteinWords.contains(where: { text.contains($0) }) { result.append(.protein) }

        let sugarWords = ["candy", "chocolate", "cake", "cookie", "brownie", "muffin", "donut",
                          "pastry", "juice", "soda", "lemonade", "sugar", "honey", "syrup",
                          "jam", "jelly", "ice cream", "gelato", "sorbet", "dessert", "pie",
                          "waffle", "pancake", "sweet", "halwa", "ladoo", "mithai", "gulab"]
        if sugarWords.contains(where: { text.contains($0) }) { result.append(.sugar) }

        let fiberWords = ["broccoli", "spinach", "kale", "carrot", "celery", "lettuce", "cabbage",
                          "cauliflower", "zucchini", "cucumber", "tomato", "pepper", "onion",
                          "apple", "banana", "orange", "pear", "berry", "berries", "strawberry",
                          "blueberry", "raspberry", "oat", "oatmeal", "whole grain", "whole wheat",
                          "bran", "quinoa", "brown rice", "lentil", "bean", "pea", "chickpea",
                          "vegetable", "salad", "saag", "palak", "methi", "bhindi", "gobi"]
        if fiberWords.contains(where: { text.contains($0) }) { result.append(.fiber) }

        let fatWords = ["butter", "olive oil", "avocado", "peanut", "almond", "cashew", "walnut",
                        "pecan", "pistachio", "cheese", "cream", "coconut", "bacon", "sausage",
                        "mayo", "mayonnaise", "ghee", "fried", "tahini", "hummus", "nuts", "nut butter"]
        if fatWords.contains(where: { text.contains($0) }) { result.append(.fat) }

        return result
    }
}

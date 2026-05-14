import AppIntents

struct LogFoodIntent: AppIntent {
    static var title: LocalizedStringResource = "Log Food or Drink"
    static var description = IntentDescription("Log a food or beverage event in PD Companion.")

    @Parameter(title: "Type") var type: FoodTypeIntentEnum

    @Parameter(title: "Attributes")
    var attributes: [FoodAttributeIntentEnum]

    func perform() async throws -> some IntentResult {
        // Shell: wires into SwiftData when Siri integration ships.
        // Pattern: same as LogSinemetDoseIntent — insert FoodEvent via shared ModelContainer.
        return .result()
    }
}

enum FoodTypeIntentEnum: String, AppEnum {
    case drink
    case mealSnack

    static var typeDisplayRepresentation: TypeDisplayRepresentation = "Food Type"
    static var caseDisplayRepresentations: [Self: DisplayRepresentation] = [
        .drink:    "Drink",
        .mealSnack: "Meal or Snack",
    ]
}

enum FoodAttributeIntentEnum: String, AppEnum {
    case caffeine, protein, sugar, fiber, fat

    static var typeDisplayRepresentation: TypeDisplayRepresentation = "Food Attribute"
    static var caseDisplayRepresentations: [Self: DisplayRepresentation] = [
        .caffeine: "Caffeine",
        .protein:  "Protein",
        .sugar:    "Sugar",
        .fiber:    "Fiber",
        .fat:      "Fat",
    ]
}

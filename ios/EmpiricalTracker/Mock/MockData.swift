import BodyMetrics
import Core
import Foundation

/// Representative demo data used when the app runs in mock/demo mode.
/// Mirrors the shapes returned by the live backend so the dashboard and detail
/// views render without a network connection. Values approximate a person
/// 6 months into a carnivore diet — matches the app's primary use-case.
public enum MockData {

    // MARK: - Date helpers

    private static func daysAgo(_ n: Int) -> Date {
        Calendar.current.date(byAdding: .day, value: -n, to: Date())!
    }

    // MARK: - Biomarker series

    public static let biomarkerSeries: [BiomarkerWithSeries] = [
        // Lipids
        .make(
            id: "kolesterol", nameNo: "Kolesterol", nameEn: "Total Cholesterol", unit: "mmol/L",
            refLow: 0, refHigh: 5.0, refType: .lt,
            points: [(180, 5.8), (120, 6.1), (60, 6.4), (14, 6.6), (0, 6.7)]
        ),
        .make(
            id: "ldl", nameNo: "LDL-kolesterol", nameEn: "LDL Cholesterol", unit: "mmol/L",
            refLow: 0, refHigh: 3.0, refType: .lt,
            points: [(180, 3.5), (120, 3.9), (60, 4.2), (14, 4.4), (0, 4.5)]
        ),
        .make(
            id: "hdl", nameNo: "HDL-kolesterol", nameEn: "HDL Cholesterol", unit: "mmol/L",
            refLow: 1.0, refHigh: nil, refType: .gt,
            points: [(180, 1.4), (120, 1.6), (60, 1.9), (14, 2.1), (0, 2.2)]
        ),
        .make(
            id: "tg", nameNo: "Triglyserider", nameEn: "Triglycerides", unit: "mmol/L",
            refLow: 0, refHigh: 1.7, refType: .lt,
            points: [(180, 1.2), (120, 0.9), (60, 0.7), (14, 0.65), (0, 0.6)]
        ),
        .make(
            // Atherogenic-particle count — the lean-mass hyper-responder marker.
            id: "apob", nameNo: "ApoB", nameEn: "Apolipoprotein B", unit: "g/L",
            refLow: 0, refHigh: 1.2, refType: .lt,
            points: [(180, 0.95), (120, 1.05), (60, 1.15), (14, 1.20), (0, 1.25)]
        ),
        .make(
            // Genetic risk modifier — measured once, largely stable.
            id: "lpa", nameNo: "Lp(a)", nameEn: "Lipoprotein (a)", unit: "nmol/L",
            refLow: 0, refHigh: 75, refType: .lt,
            points: [(180, 42), (0, 44)]
        ),

        // Glycaemic / metabolic
        .make(
            id: "hba1c", nameNo: "HbA1c", nameEn: "HbA1c", unit: "mmol/mol",
            refLow: 0, refHigh: 48, refType: .lt,
            points: [(180, 38), (90, 36), (30, 34), (0, 33)]
        ),
        .make(
            // Rises with the high purine load of an all-meat diet (gout / renal load).
            id: "urat", nameNo: "Urat", nameEn: "Uric acid", unit: "µmol/L",
            refLow: 200, refHigh: 420, refType: .bounded,
            points: [(180, 330), (90, 360), (30, 390), (0, 410)]
        ),

        // Liver
        .make(
            id: "alt", nameNo: "ALT", nameEn: "ALT", unit: "U/L",
            refLow: 0, refHigh: 45, refType: .lt,
            points: [(90, 28), (30, 25), (0, 23)]
        ),
        .make(
            id: "ggt", nameNo: "GGT", nameEn: "GGT", unit: "U/L",
            refLow: 0, refHigh: 45, refType: .lt,
            points: [(90, 22), (30, 19), (0, 18)]
        ),

        // Renal
        .make(
            id: "kreatinin", nameNo: "Kreatinin", nameEn: "Creatinine", unit: "µmol/L",
            refLow: 60, refHigh: 105, refType: .bounded,
            points: [(90, 88), (30, 92), (0, 95)]
        ),

        // Nutrients
        .make(
            id: "ferritin", nameNo: "Ferritin", nameEn: "Ferritin", unit: "µg/L",
            refLow: 30, refHigh: 400, refType: .bounded,
            points: [(120, 85), (60, 110), (14, 130), (0, 145)]
        ),
        .make(
            id: "b12", nameNo: "B12", nameEn: "Vitamin B12", unit: "pmol/L",
            refLow: 145, refHigh: 569, refType: .bounded,
            points: [(90, 320), (30, 380), (0, 410)]
        ),
        .make(
            id: "vitd", nameNo: "Vitamin D", nameEn: "Vitamin D (25-OH)", unit: "nmol/L",
            refLow: 50, refHigh: 125, refType: .bounded,
            points: [(180, 42), (90, 65), (30, 78), (0, 82)]
        ),

        // Electrolytes (incl. the refeeding-syndrome pair watched when fasting)
        .make(
            id: "magnesium", nameNo: "Magnesium", nameEn: "Magnesium", unit: "mmol/L",
            refLow: 0.71, refHigh: 0.94, refType: .bounded,
            points: [(90, 0.84), (30, 0.82), (0, 0.81)]
        ),
        .make(
            id: "fosfat", nameNo: "Fosfat", nameEn: "Phosphate", unit: "mmol/L",
            refLow: 0.85, refHigh: 1.65, refType: .bounded,
            points: [(90, 1.10), (30, 1.05), (0, 1.00)]
        ),
    ]

    // MARK: - Diet events

    public static let dietEvents: [DietEvent] = [
        DietEvent(
            id: "evt-1",
            label: "Started carnivore diet",
            kind: .diet,
            startedOn: daysAgo(180),
            endedOn: nil,
            note: "Beef, eggs, organ meat only. Zero plants."
        ),
        DietEvent(
            id: "evt-2",
            label: "72-hour fast",
            kind: .fast,
            startedOn: daysAgo(120),
            endedOn: daysAgo(117),
            note: "Water + salt only."
        ),
        DietEvent(
            id: "evt-3",
            label: "Added vitamin D supplement",
            kind: .supplement,
            startedOn: daysAgo(90),
            endedOn: nil,
            note: "4000 IU daily."
        ),
    ]

    // MARK: - Food diary (Sprint 6)

    /// A representative carnivore-diet day: whole foods from Matvaretabellen / USDA plus
    /// one branded OFF product. Demonstrates source badges and sodium / saturated-fat totals.
    public static let foodEntries: [FoodEntry] = [
        FoodEntry(
            id: "fe-1", loggedOn: .now, meal: .breakfast,
            foodName: "Egg, whole, raw", quantityG: 150,
            energyKcal: 215, carbsG: 1.7, proteinG: 18.9, fatG: 15.0,
            saturatedFatG: 4.6, sodiumMg: 213, source: .usda
        ),
        FoodEntry(
            id: "fe-2", loggedOn: .now, meal: .breakfast,
            foodName: "Smør", brand: nil, quantityG: 20,
            energyKcal: 149, carbsG: 0.1, proteinG: 0.2, fatG: 16.4,
            saturatedFatG: 10.4, sodiumMg: 2, source: .mvt
        ),
        FoodEntry(
            id: "fe-3", loggedOn: .now, meal: .dinner,
            foodName: "Storfe, ribeye, rå", quantityG: 300,
            energyKcal: 873, carbsG: 0, proteinG: 62.4, fatG: 69.0,
            saturatedFatG: 28.5, sodiumMg: 156, source: .mvt
        ),
        FoodEntry(
            id: "fe-4", loggedOn: .now, meal: .snack,
            foodName: "Jarlsberg", brand: "TINE", barcode: "7038010009457", quantityG: 40,
            energyKcal: 137, carbsG: 0, proteinG: 10.8, fatG: 10.6,
            saturatedFatG: 6.9, sodiumMg: 244, source: .off
        ),
    ]

    // MARK: - Meal plans (Sprint 7)

    public static let mealPlans: [MealPlan] = [
        MealPlan(id: "mp-1", name: "Carnivore week", description: "Beef, eggs, butter — zero plants."),
        MealPlan(id: "mp-2", name: "Low-carb reset", description: "Under 30 g carbs/day."),
    ]

    /// A couple of planned meals across the current week, demonstrating per-day energy
    /// totals, the done toggle, plan grouping, and a free-text (no-macro) entry.
    public static let plannedMeals: [PlannedMeal] = [
        PlannedMeal(
            id: "pm-1", scheduledOn: Date(), meal: .breakfast,
            foodName: "Egg, whole, raw", quantityG: 150,
            energyKcal: 215, carbsG: 1.7, proteinG: 18.9, fatG: 15.0,
            done: false, planId: "mp-1"
        ),
        PlannedMeal(
            id: "pm-2", scheduledOn: Date(), meal: .dinner,
            foodName: "Storfe, ribeye, rå", quantityG: 300,
            energyKcal: 873, carbsG: 0, proteinG: 62.4, fatG: 69.0,
            done: false, planId: "mp-1"
        ),
        PlannedMeal(
            id: "pm-3", scheduledOn: Calendar.current.date(byAdding: .day, value: 1, to: Date())!,
            meal: .lunch, foodName: "Ribeye + eggs", note: "Free-text — no macros published.",
            done: false, planId: "mp-1"
        ),
    ]

    // MARK: - Body metrics (Sprint 8)

    /// A carnivore-diet weight-loss arc with periodic waist and blood-pressure readings,
    /// demonstrating each metric's own series (charts skip the rows where it is null) and
    /// the diet-event correlation overlay sharing the same timeline.
    public static let bodyMetrics: [BodyMetric] = [
        BodyMetric(id: "bm-1", measuredOn: daysAgo(180), weightKg: 92.4, waistCm: 104,
                   systolic: 138, diastolic: 88, note: "Baseline before carnivore."),
        BodyMetric(id: "bm-2", measuredOn: daysAgo(150), weightKg: 89.1, waistCm: 101),
        BodyMetric(id: "bm-3", measuredOn: daysAgo(120), weightKg: 86.7, waistCm: 98,
                   systolic: 131, diastolic: 84),
        BodyMetric(id: "bm-4", measuredOn: daysAgo(90), weightKg: 84.2, waistCm: 95,
                   systolic: 126, diastolic: 81),
        BodyMetric(id: "bm-5", measuredOn: daysAgo(60), weightKg: 82.0, waistCm: 92),
        BodyMetric(id: "bm-6", measuredOn: daysAgo(30), weightKg: 80.3, waistCm: 90,
                   systolic: 120, diastolic: 78),
        BodyMetric(id: "bm-7", measuredOn: daysAgo(0), weightKg: 79.1, waistCm: 89,
                   systolic: 118, diastolic: 76, note: "Down 13 kg."),
    ]

    // MARK: - Activity metrics (HealthKit — steps, active energy, exercise)

    public static let activityMetrics: [ActivityMetric] = (0..<90).map { i in
        let d = daysAgo(89 - i)
        let baseSteps = 7_500 + Int.random(in: -2_000...3_000)
        let energy = Double(baseSteps) * 0.045 + Double.random(in: -50...80)
        let exercise = max(0, baseSteps / 500 - 5 + Int.random(in: -5...15))
        return ActivityMetric(
            id: "am-\(i)",
            measuredOn: d,
            steps: baseSteps,
            activeEnergyKcal: energy,
            exerciseMinutes: exercise
        )
    }
}

// MARK: - Builder

private extension BiomarkerWithSeries {
    static func make(
        id: String,
        nameNo: String,
        nameEn: String,
        unit: String,
        refLow: Double?,
        refHigh: Double?,
        refType: BiomarkerInfo.RefType,
        points: [(daysAgo: Int, value: Double)]
    ) -> BiomarkerWithSeries {
        let info = BiomarkerInfo(
            id: id,
            nameNo: nameNo,
            nameEn: nameEn,
            unit: unit,
            refRangeRaw: buildRefRaw(low: refLow, high: refHigh, type: refType),
            refLow: refLow,
            refHigh: refHigh,
            refType: refType
        )
        let cal = Calendar.current
        let series: [ResultPoint] = points.map { (days, value) in
            let date = cal.date(byAdding: .day, value: -days, to: Date())!
            let inRange: Bool? = switch refType {
            case .bounded: (refLow.map { value >= $0 } ?? true) && (refHigh.map { value <= $0 } ?? true)
            case .lt:  refHigh.map { value <= $0 }
            case .gt:  refLow.map  { value >= $0 }
            case .none: nil
            }
            return ResultPoint(testedAt: date, value: value, inRange: inRange)
        }
        return BiomarkerWithSeries(biomarker: info, series: series.sorted { $0.testedAt < $1.testedAt })
    }

    private static func buildRefRaw(low: Double?, high: Double?, type: BiomarkerInfo.RefType) -> String {
        switch type {
        case .lt:      return "< \(high ?? 0)"
        case .gt:      return "> \(low ?? 0)"
        case .bounded: return "\(low ?? 0) - \(high ?? 0)"
        case .none:    return "—"
        }
    }
}

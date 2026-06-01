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

        // Glycaemic
        .make(
            id: "hba1c", nameNo: "HbA1c", nameEn: "HbA1c", unit: "mmol/mol",
            refLow: 0, refHigh: 48, refType: .lt,
            points: [(180, 38), (90, 36), (30, 34), (0, 33)]
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

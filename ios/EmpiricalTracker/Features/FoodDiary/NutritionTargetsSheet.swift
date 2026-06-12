import BodyMetrics
import Core
import SwiftUI

/// Editor for the optional daily intake targets (energy / protein / carb ceiling).
/// All fields are the user's own numbers; the only convenience is the protein
/// g/kg quick-set, computed from the latest tracked body weight (ADR-017) so a
/// "1.6 g/kg" intention becomes a concrete gram figure without mental arithmetic.
struct NutritionTargetsSheet: View {
    @Environment(AppEnvironment.self) private var env
    @Environment(\.dismiss) private var dismiss

    @State private var energyText = ""
    @State private var proteinText = ""
    @State private var carbsText = ""

    private static let proteinPerKgPresets: [Double] = [1.2, 1.6, 2.0]

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    targetField(
                        String(localized: "food.targets.energy"),
                        text: $energyText,
                        unit: String(localized: "food.unit.kcal")
                    )
                } footer: {
                    Text(String(localized: "food.targets.footer"))
                }

                Section {
                    targetField(
                        String(localized: "food.targets.protein"),
                        text: $proteinText,
                        unit: String(localized: "food.unit.g")
                    )
                    if let weight = latestWeightKg {
                        proteinPerKgRow(weightKg: weight)
                    }
                }

                Section {
                    targetField(
                        String(localized: "food.targets.carbs"),
                        text: $carbsText,
                        unit: String(localized: "food.unit.g")
                    )
                } footer: {
                    Text(String(localized: "food.targets.carbs.footer"))
                }

                if env.nutritionTargets.hasAnyTarget {
                    Section {
                        Button(role: .destructive) {
                            env.nutritionTargets.energyKcal = nil
                            env.nutritionTargets.proteinG = nil
                            env.nutritionTargets.carbsMaxG = nil
                            dismiss()
                        } label: {
                            Label(String(localized: "food.targets.clear"), systemImage: "xmark.circle")
                        }
                    }
                }
            }
            .navigationTitle(String(localized: "food.targets.title"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(String(localized: "common.cancel")) { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(String(localized: "common.save")) { save() }
                        .fontWeight(.semibold)
                }
            }
            .task {
                // Prefill from the stored targets; fetch metrics so the g/kg
                // quick-set has a body weight to work from.
                energyText  = Self.format(env.nutritionTargets.energyKcal)
                proteinText = Self.format(env.nutritionTargets.proteinG)
                carbsText   = Self.format(env.nutritionTargets.carbsMaxG)
                if env.bodyMetrics.metrics.isEmpty {
                    await env.bodyMetrics.load()
                }
            }
        }
        .presentationDetents([.medium, .large])
    }

    // MARK: - Rows

    private func targetField(_ label: String, text: Binding<String>, unit: String) -> some View {
        HStack {
            Text(label).foregroundStyle(Color.textSecondary)
            Spacer()
            TextField("—", text: text)
                .keyboardType(.decimalPad)
                .multilineTextAlignment(.trailing)
                .frame(maxWidth: 90)
            Text(unit).foregroundStyle(Color.textMuted)
        }
    }

    private func proteinPerKgRow(weightKg: Double) -> some View {
        let weightString = "\(weightKg.formatted(.number.precision(.fractionLength(0...1)))) kg"
        return VStack(alignment: .leading, spacing: 8) {
            Text(String(localized: "food.targets.protein.helper \(weightString)"))
                .font(.bodySmall)
                .foregroundStyle(Color.textMuted)
            HStack(spacing: 8) {
                ForEach(Self.proteinPerKgPresets, id: \.self) { perKg in
                    Button {
                        proteinText = Self.format((perKg * weightKg).rounded())
                    } label: {
                        Text(verbatim: "\(perKg.formatted(.number.precision(.fractionLength(1)))) g/kg")
                            .font(.labelMedium)
                    }
                    .buttonStyle(.bordered)
                    .buttonBorderShape(.capsule)
                    .tint(Color.accent)
                }
            }
        }
        .padding(.vertical, 2)
    }

    // MARK: - Data

    /// Most recent tracked weight, used only to translate g/kg into grams.
    private var latestWeightKg: Double? {
        env.bodyMetrics.metrics
            .sorted { $0.measuredOn < $1.measuredOn }
            .compactMap(\.weightKg)
            .last
    }

    // MARK: - Save / parse

    private func save() {
        env.nutritionTargets.energyKcal = Self.parse(energyText)
        env.nutritionTargets.proteinG   = Self.parse(proteinText)
        env.nutritionTargets.carbsMaxG  = Self.parse(carbsText)
        dismiss()
    }

    private static func format(_ value: Double?) -> String {
        guard let value else { return "" }
        return value.formatted(.number.precision(.fractionLength(0)).grouping(.never))
    }

    /// Parses a number, tolerating Norwegian decimal commas (same as `LogFoodSheet`).
    private static func parse(_ text: String) -> Double? {
        let trimmed = text.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return nil }
        guard let value = Double(trimmed.replacingOccurrences(of: ",", with: ".")), value > 0 else {
            return nil
        }
        return value
    }
}

#Preview {
    NutritionTargetsSheet()
        .environment(AppEnvironment.preview())
}

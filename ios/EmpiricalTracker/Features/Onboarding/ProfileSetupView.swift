import Core
import SwiftUI

/// First-run profile setup, shown once after consent for a newly registered
/// account (gated by `UserProfileStore.hasCompletedSetup` in `RootView`).
///
/// Lets the user pick their unit system and optionally record height, current
/// weight, waist, and biological sex — or **skip** entirely / **sync with Apple
/// Health** instead. Nothing here is required: the screen seeds the profile and
/// the Body tab's first data point, but the app is fully usable without it.
struct ProfileSetupView: View {
    @Environment(AppEnvironment.self) private var env
    @State private var viewModel: ProfileSetupViewModel?

    var body: some View {
        ScrollView {
            if let vm = viewModel {
                content(vm)
            }
        }
        .scrollDismissesKeyboard(.interactively)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.bgBase)
        .task {
            if viewModel == nil {
                viewModel = ProfileSetupViewModel(
                    profile: env.userProfile,
                    settings: env.settings,
                    bodyMetrics: env.bodyMetrics
                )
            }
        }
    }

    @ViewBuilder
    private func content(_ vm: ProfileSetupViewModel) -> some View {
        @Bindable var vm = vm
        VStack(spacing: 24) {
            header
            unitsCard($vm)
            measurementsCard($vm)
            if env.healthSyncState.connection != .unavailable {
                appleHealthCard
            }
            if let error = vm.errorMessage ?? vm.validationError {
                errorBanner(error)
            }
            actions(vm)
        }
        .padding(.horizontal, 20)
        .padding(.top, 44)
        .padding(.bottom, 32)
        .frame(maxWidth: .infinity)
    }

    // MARK: - Header

    private var header: some View {
        VStack(spacing: 14) {
            CircleIconBadge("person.text.rectangle", tint: .accent, size: 64)
            Text(String(localized: "profile.setup.title"))
                .font(.displayMedium)
                .foregroundStyle(Color.textPrimary)
                .multilineTextAlignment(.center)
            Text(String(localized: "profile.setup.subtitle"))
                .font(.bodyMedium)
                .foregroundStyle(Color.textSecondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    // MARK: - Units

    private func unitsCard(_ vm: Bindable<ProfileSetupViewModel>) -> some View {
        SoftCard {
            VStack(alignment: .leading, spacing: 10) {
                cardLabel(String(localized: "profile.units.label"))
                Picker(String(localized: "profile.units.label"), selection: vm.units) {
                    ForEach(MeasurementSystem.allCases) { system in
                        Text(system.label).tag(system)
                    }
                }
                .pickerStyle(.segmented)
                .accessibilityLabel(String(localized: "profile.units.label"))
            }
        }
    }

    // MARK: - Measurements

    private func measurementsCard(_ vm: Bindable<ProfileSetupViewModel>) -> some View {
        SoftCard {
            VStack(alignment: .leading, spacing: 18) {
                cardLabel(String(localized: "profile.measurements.label"))

                heightField(vm)
                Divider().overlay(Color.borderSubtle)
                fieldRow(
                    title: String(localized: "profile.weight"),
                    text: vm.weight,
                    unit: vm.wrappedValue.units.weightUnit
                )
                Divider().overlay(Color.borderSubtle)
                fieldRow(
                    title: String(localized: "profile.waist"),
                    text: vm.waist,
                    unit: vm.wrappedValue.units.lengthUnit
                )
                Divider().overlay(Color.borderSubtle)
                sexRow(vm)

                Text(String(localized: "profile.measurements.hint"))
                    .font(.bodySmall)
                    .foregroundStyle(Color.textMuted)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    @ViewBuilder
    private func heightField(_ vm: Bindable<ProfileSetupViewModel>) -> some View {
        switch vm.wrappedValue.units {
        case .metric:
            fieldRow(
                title: String(localized: "profile.height"),
                text: vm.heightCm,
                unit: String(localized: "units.cm")
            )
        case .imperial:
            HStack(spacing: 12) {
                Text(String(localized: "profile.height"))
                    .font(.bodyMedium)
                    .foregroundStyle(Color.textSecondary)
                Spacer()
                numberField(vm.heightFeet, placeholder: "—", width: 50)
                Text(String(localized: "units.ft"))
                    .font(.bodySmall)
                    .foregroundStyle(Color.textMuted)
                numberField(vm.heightInches, placeholder: "—", width: 50)
                Text(String(localized: "units.in"))
                    .font(.bodySmall)
                    .foregroundStyle(Color.textMuted)
            }
            .accessibilityElement(children: .combine)
        }
    }

    private func sexRow(_ vm: Bindable<ProfileSetupViewModel>) -> some View {
        HStack {
            Text(String(localized: "profile.sex.label"))
                .font(.bodyMedium)
                .foregroundStyle(Color.textSecondary)
            Spacer()
            Menu {
                Picker(String(localized: "profile.sex.label"), selection: vm.biologicalSex) {
                    Text(String(localized: "profile.sex.unset")).tag(BiologicalSex?.none)
                    ForEach(BiologicalSex.allCases) { sex in
                        Text(sex.label).tag(BiologicalSex?.some(sex))
                    }
                }
            } label: {
                HStack(spacing: 4) {
                    Text(vm.wrappedValue.biologicalSex?.label ?? String(localized: "profile.sex.unset"))
                        .font(.bodyMedium)
                        .foregroundStyle(vm.wrappedValue.biologicalSex == nil ? Color.textMuted : Color.textPrimary)
                    Image(systemName: "chevron.up.chevron.down")
                        .font(.labelMedium)
                        .foregroundStyle(Color.textMuted)
                }
            }
            .accessibilityLabel(String(localized: "profile.sex.label"))
        }
    }

    // MARK: - Apple Health

    private var appleHealthCard: some View {
        SoftCard {
            HStack(spacing: 14) {
                CircleIconBadge("heart.text.square.fill", tint: .outRange, size: 44)
                VStack(alignment: .leading, spacing: 3) {
                    Text(String(localized: "profile.health.title"))
                        .font(.headlineSmall)
                        .foregroundStyle(Color.textPrimary)
                    Text(healthSubtitle)
                        .font(.bodySmall)
                        .foregroundStyle(Color.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 8)
                if env.healthSyncState.connection == .connected {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(Color.inRange)
                        .font(.system(size: 22))
                        .accessibilityLabel(String(localized: "profile.health.connected"))
                } else if env.healthSyncState.isSyncing {
                    ProgressView()
                } else {
                    Button(String(localized: "profile.health.connect")) {
                        Task { await env.healthSyncState.connect() }
                    }
                    .buttonStyle(.bordered)
                    .tint(Color.accent)
                }
            }
        }
    }

    private var healthSubtitle: String {
        env.healthSyncState.connection == .connected
            ? String(localized: "profile.health.connected.subtitle")
            : String(localized: "profile.health.subtitle")
    }

    // MARK: - Actions

    private func actions(_ vm: ProfileSetupViewModel) -> some View {
        VStack(spacing: 12) {
            Button {
                Task { await vm.save() }
            } label: {
                HStack(spacing: 8) {
                    if vm.isSaving { ProgressView().tint(.white) }
                    Text(String(localized: "profile.save"))
                }
                .frame(maxWidth: .infinity)
            }
            .buttonStyle(PrimaryButtonStyle())
            .disabled(!vm.canSave || vm.isSaving)
            .opacity(vm.canSave ? 1 : 0.5)

            Button {
                vm.persistUnitsOnly()
                vm.skip()
            } label: {
                Text(String(localized: "profile.skip"))
                    .font(.bodyMedium)
                    .foregroundStyle(Color.textSecondary)
            }
            .disabled(vm.isSaving)
            .accessibilityHint(String(localized: "profile.skip.hint"))
        }
    }

    // MARK: - Reusable pieces

    private func cardLabel(_ text: String) -> some View {
        Text(text)
            .font(.labelLarge)
            .foregroundStyle(Color.textSecondary)
    }

    private func fieldRow(title: String, text: Binding<String>, unit: String) -> some View {
        HStack {
            Text(title)
                .font(.bodyMedium)
                .foregroundStyle(Color.textSecondary)
            Spacer()
            numberField(text, placeholder: "—", width: 90)
            Text(unit)
                .font(.bodySmall)
                .foregroundStyle(Color.textMuted)
                .frame(minWidth: 28, alignment: .leading)
        }
    }

    private func numberField(_ text: Binding<String>, placeholder: String, width: CGFloat) -> some View {
        TextField(placeholder, text: text)
            .keyboardType(.decimalPad)
            .multilineTextAlignment(.trailing)
            .font(.bodyLarge)
            .foregroundStyle(Color.textPrimary)
            .frame(maxWidth: width)
    }

    private func errorBanner(_ message: String) -> some View {
        Label(message, systemImage: "exclamationmark.triangle.fill")
            .font(.bodySmall)
            .foregroundStyle(Color.outRange)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(12)
            .background(Color.outRange.opacity(0.1), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }
}

// MARK: - Preview

#Preview {
    ProfileSetupView()
        .environment(AppEnvironment.preview())
}

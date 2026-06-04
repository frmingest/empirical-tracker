import Testing
import Foundation
@testable import EmpiricalTracker

// These tests deliberately depend only on the app module (no Core/BodyMetrics
// imports), since the unit-test target does not link the feature packages. They
// cover the bug-prone pure logic: unit conversions and profile persistence.

// MARK: - Unit conversions

struct UnitConvertTests {

    @Test func poundsRoundTrip() {
        #expect(abs(UnitConvert.kg(fromPounds: 220.462) - 100) < 0.001)
        #expect(abs(UnitConvert.pounds(fromKg: 100) - 220.462) < 0.001)
    }

    @Test func inchesRoundTrip() {
        #expect(UnitConvert.cm(fromInches: 10) == 25.4)
        #expect(abs(UnitConvert.inches(fromCm: 25.4) - 10) < 0.001)
    }

    @Test func feetInchesToCm() {
        // 5 ft 10 in == 70 in == 177.8 cm
        #expect(abs(UnitConvert.cm(fromFeet: 5, inches: 10) - 177.8) < 0.001)
    }

    @Test func cmToFeetInchesRounds() {
        let (ft, inch) = UnitConvert.feetInches(fromCm: 177.8)
        #expect(ft == 5)
        #expect(inch == 10)
    }

    @Test func defaultMeasurementSystemIsMetric() {
        #expect(MeasurementSystem.default == .metric)
    }
}

// MARK: - Profile store persistence

@MainActor
struct UserProfileStoreTests {

    private func freshDefaults() -> UserDefaults {
        let suite = "test.profile.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        return defaults
    }

    @Test func startsEmpty() {
        let store = UserProfileStore(defaults: freshDefaults())
        #expect(store.heightCm == nil)
        #expect(store.biologicalSex == nil)
        #expect(store.hasCompletedSetup == false)
    }

    @Test func persistsAcrossInstances() {
        let defaults = freshDefaults()
        let store = UserProfileStore(defaults: defaults)
        store.update(heightCm: 182, biologicalSex: .male)
        store.markSetupComplete()

        let reloaded = UserProfileStore(defaults: defaults)
        #expect(reloaded.heightCm == 182)
        #expect(reloaded.biologicalSex == .male)
        #expect(reloaded.hasCompletedSetup)
    }

    @Test func clearingFieldsRemovesThem() {
        let defaults = freshDefaults()
        let store = UserProfileStore(defaults: defaults)
        store.update(heightCm: 170, biologicalSex: .female)
        store.update(heightCm: nil, biologicalSex: nil)

        let reloaded = UserProfileStore(defaults: defaults)
        #expect(reloaded.heightCm == nil)
        #expect(reloaded.biologicalSex == nil)
    }

    @Test func resetClearsEverything() {
        let defaults = freshDefaults()
        let store = UserProfileStore(defaults: defaults)
        store.update(heightCm: 175, biologicalSex: .other)
        store.markSetupComplete()
        store.reset()

        #expect(store.heightCm == nil)
        #expect(store.hasCompletedSetup == false)
        let reloaded = UserProfileStore(defaults: defaults)
        #expect(reloaded.hasCompletedSetup == false)
    }
}

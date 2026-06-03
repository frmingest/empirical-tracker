import Testing
import Foundation
import Core
@testable import Biomarkers

/// Tests for the ADR-015 panel-expansion markers in the iOS clinical port:
/// triglycerides, ApoB, Lp(a), uric acid, magnesium, phosphate. These verify the
/// markers categorise correctly, resolve to a canonical key, and appear under the
/// diet focuses that clinically need them — in particular the refeeding
/// electrolytes (Mg + phosphate) on the Fasting focus.
struct DietProfileTests {

    // MARK: - Category placement

    @Test func newMarkersCategorise() {
        #expect(biomarkerCategory(for: "Triglyserider") == .lipids)
        #expect(biomarkerCategory(for: "ApoB") == .lipids)
        #expect(biomarkerCategory(for: "Apolipoprotein B") == .lipids)
        #expect(biomarkerCategory(for: "Lp(a)") == .lipids)
        #expect(biomarkerCategory(for: "Lipoprotein (a)") == .lipids)
        #expect(biomarkerCategory(for: "Urat") == .metabolic)
        #expect(biomarkerCategory(for: "Urinsyre") == .metabolic)
        #expect(biomarkerCategory(for: "Magnesium") == .electrolytes)
        #expect(biomarkerCategory(for: "Fosfat") == .electrolytes)
    }

    // MARK: - Canonical key resolution

    @Test func newMarkersResolveKeys() {
        #expect(markerKey(for: "Triglyserider") == .triglycerides)
        #expect(markerKey(for: "ApoB") == .apoB)
        #expect(markerKey(for: "Apolipoprotein B") == .apoB)
        #expect(markerKey(for: "Lp(a)") == .lpA)
        #expect(markerKey(for: "Lipoprotein (a)") == .lpA)
        #expect(markerKey(for: "Urat") == .uricAcid)
        #expect(markerKey(for: "Magnesium") == .magnesium)
        #expect(markerKey(for: "Fosfat") == .phosphate)
    }

    /// ApoB and Lp(a) must not steal each other's identity.
    @Test func apoBAndLpADoNotCollide() {
        #expect(markerKey(for: "Apolipoprotein B") != .lpA)
        #expect(markerKey(for: "Lipoprotein (a)") != .apoB)
    }

    // MARK: - Diet relevance

    /// The ADR-015 headline fix: refeeding syndrome is defined by falling
    /// phosphate / magnesium / potassium, so all three (plus sodium) must be
    /// visible on the Fasting focus — not potassium alone.
    @Test func fastingShowsRefeedingElectrolytes() {
        for name in ["Natrium", "Kalium", "Magnesium", "Fosfat"] {
            #expect(isDietRelevant(name, diet: .fasting, customMarkers: []),
                    "\(name) should be visible on the Fasting focus")
        }
    }

    @Test func triglyceridesVisibleAcrossDietLipidViews() {
        #expect(isDietRelevant("Triglyserider", diet: .carnivore, customMarkers: []))
        #expect(isDietRelevant("Triglyserider", diet: .lowCarb, customMarkers: []))
        #expect(isDietRelevant("Triglyserider", diet: .fasting, customMarkers: []))
    }

    @Test func atherogenicParticleMarkersVisible() {
        #expect(isDietRelevant("ApoB", diet: .carnivore, customMarkers: []))
        #expect(isDietRelevant("Lp(a)", diet: .carnivore, customMarkers: []))
        #expect(isDietRelevant("ApoB", diet: .lowCarb, customMarkers: []))
        #expect(isDietRelevant("ApoB", diet: .fasting, customMarkers: []))
        #expect(isDietRelevant("Lp(a)", diet: .fasting, customMarkers: []))
    }

    /// Uric acid: raised by high-purine meat intake and by fasting — carnivore and
    /// fasting only, not general low-carb (ADR-015).
    @Test func uricAcidOnCarnivoreAndFastingOnly() {
        #expect(isDietRelevant("Urat", diet: .carnivore, customMarkers: []))
        #expect(isDietRelevant("Urat", diet: .fasting, customMarkers: []))
        #expect(!isDietRelevant("Urat", diet: .lowCarb, customMarkers: []))
    }
}

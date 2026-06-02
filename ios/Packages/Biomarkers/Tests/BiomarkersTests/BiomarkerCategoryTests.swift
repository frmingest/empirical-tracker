import Testing
import Foundation
@testable import Biomarkers

/// Tests for the plain-language category summaries shown atop the per-category view.
struct BiomarkerCategoryTests {

    @Test("Every category exposes a non-empty, lay-friendly summary")
    func everyCategoryHasSummary() {
        for category in BiomarkerCategory.allCases {
            let summary = category.summary
            #expect(!summary.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                    "\(category.displayName) is missing a summary")
            // Long enough to actually explain something, short enough to stay readable.
            #expect(summary.count >= 80, "\(category.displayName) summary is too terse")
            #expect(summary.count <= 600, "\(category.displayName) summary is too long")
        }
    }

    @Test("Summaries avoid markup and read as prose")
    func summariesAreProse() {
        for category in BiomarkerCategory.allCases {
            let summary = category.summary
            #expect(!summary.contains("  "), "\(category.displayName) summary has double spaces")
            #expect(summary.last == "." || summary.last == "!", "\(category.displayName) summary should end with a sentence")
        }
    }
}

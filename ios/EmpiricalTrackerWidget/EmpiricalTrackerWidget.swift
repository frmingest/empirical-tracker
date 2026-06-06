import WidgetKit
import SwiftUI

/// Entry point for the widget bundle — registers all three widgets.
@main
struct EmpiricalTrackerWidgetBundle: WidgetBundle {
    var body: some Widget {
        BiomarkerPanelWidget()
        WeightTrendWidget()
        MacrosDiaryWidget()
    }
}

// NineWidgetBundle.swift — entry point of the NineWidgets extension
// (PRD-3 §3a). Two widgets: the daily board state and the streak accessory.
import SwiftUI
import WidgetKit

@main
struct NineWidgetBundle: WidgetBundle {
    var body: some Widget {
        NineDailyWidget()
        NineStreakWidget()
    }
}

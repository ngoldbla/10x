// NineWidgetBundle.swift — entry point of the NineWidgets extension
// (PRD-3). Three widgets: glanceable daily state, the streak accessory,
// and the playable large board.
import SwiftUI
import WidgetKit

@main
struct NineWidgetBundle: WidgetBundle {
    var body: some Widget {
        NineDailyWidget()
        NineStreakWidget()
        NineBoardWidget()
    }
}

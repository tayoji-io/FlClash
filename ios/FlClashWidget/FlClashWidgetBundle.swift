import SwiftUI
import WidgetKit

@main
struct FlClashWidgetBundle: WidgetBundle {
    var body: some Widget {
        TunnelWidget()
        if #available(iOS 18.0, *) {
            TunnelControl()
        }
    }
}

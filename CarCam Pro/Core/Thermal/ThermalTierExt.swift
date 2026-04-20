import SwiftUI

/// UI helpers for rendering thermal tier status in the dashboard/settings.
extension ThermalTier {
    var color: Color {
        switch self {
        case .nominal:  return CCTheme.green
        case .fair:     return CCTheme.cyan
        case .serious:  return CCTheme.amber
        case .critical: return CCTheme.red
        }
    }
}

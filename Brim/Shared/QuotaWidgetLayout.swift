import SwiftUI

public enum WidgetFamilyShape {
    case small
    case medium

    public var slotCount: Int {
        switch self {
        case .small: return 2
        case .medium: return QuotaAccountDefaults.mediumWidgetSlotCount
        }
    }

    public var ringDiameter: CGFloat {
        switch self {
        case .small: return 64
        case .medium: return 64
        }
    }

    public var ringSlotWidth: CGFloat { ringDiameter + 2 }

    public var accountSpacing: CGFloat {
        switch self {
        case .small: return 12
        case .medium: return 12
        }
    }

    public var accountSlotWidth: CGFloat {
        switch self {
        case .small: return 68
        case .medium: return 68
        }
    }

    public var accountLabelSpacing: CGFloat { 4 }
    public var weeklyLabelFontSize: CGFloat { 10 }
    public var weeklyLabelHeight: CGFloat { 12 }
    public var sessionLabelFontSize: CGFloat { 13 }
    public var sessionLabelHeight: CGFloat { 15 }

    /// Half the label stack height — shifts pager chevrons up so they center on the rings.
    public var pagerRingCenteringOffset: CGFloat {
        (accountLabelSpacing + sessionLabelHeight + 1 + weeklyLabelHeight) / 2
    }

    public var horizontalPadding: CGFloat {
        switch self {
        case .small: return 15
        case .medium: return 16
        }
    }

    public var cornerRadius: CGFloat { 24 }

    public var controlButtonSize: CGFloat {
        switch self {
        case .small: return 22
        case .medium: return 24
        }
    }

    public var controlIconSize: CGFloat {
        switch self {
        case .small: return 9
        case .medium: return 10
        }
    }

    public var controlButtonPadding: CGFloat { 7 }

    public var controlSpacing: CGFloat {
        switch self {
        case .small: return 5
        case .medium: return 6
        }
    }

    public var pagerButtonSize: CGFloat {
        switch self {
        case .small: return 16
        case .medium: return 18
        }
    }

    public var pagerIconSize: CGFloat {
        switch self {
        case .small: return 10
        case .medium: return 11
        }
    }

    public var pagerSpacing: CGFloat {
        switch self {
        case .small: return 5
        case .medium: return 7
        }
    }






    public var showsDetails: Bool {
        switch self {
        case .small: return false
        case .medium: return true
        }
    }
}

public enum PagerDirection {
    case left
    case right
}

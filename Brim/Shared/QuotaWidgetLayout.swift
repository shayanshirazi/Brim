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
        case .small: return 58
        case .medium: return 58
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
        case .small: return 62
        case .medium: return 62
        }
    }

    public var accountLabelSpacing: CGFloat { 8 }
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
        case .small: return 8
        case .medium: return 10
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

    public var controlButtonPadding: CGFloat { 12 }

    public var controlSpacing: CGFloat {
        switch self {
        case .small: return 5
        case .medium: return 6
        }
    }

    public var pagerButtonSize: CGFloat {
        switch self {
        case .small: return 12
        case .medium: return 12
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
        case .small: return 4
        case .medium: return 4
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

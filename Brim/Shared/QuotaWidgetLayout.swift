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
        case .small: return 54
        case .medium: return 52
        }
    }

    public var ringSlotWidth: CGFloat { ringDiameter + 2 }

    public var accountSpacing: CGFloat {
        switch self {
        case .small: return 13
        case .medium: return 16
        }
    }

    public var accountSlotWidth: CGFloat {
        switch self {
        case .small: return 60
        case .medium: return 58
        }
    }

    public var accountLabelSpacing: CGFloat { 6 }
    public var weeklyLabelFontSize: CGFloat { 9 }
    public var weeklyLabelHeight: CGFloat { 11 }
    public var sessionLabelFontSize: CGFloat { 18 }
    public var sessionLabelHeight: CGFloat { 21 }

    public var horizontalPadding: CGFloat {
        switch self {
        case .small: return 15
        case .medium: return 16
        }
    }

    public var verticalPadding: CGFloat {
        switch self {
        case .small: return 15
        case .medium: return 13
        }
    }

    public var accountRowBottomPadding: CGFloat {
        switch self {
        case .small: return 13
        case .medium: return 24
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

    public var controlButtonPadding: CGFloat { 10 }

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

    public var resetInfoWidth: CGFloat {
        switch self {
        case .small: return 0
        case .medium: return 220
        }
    }

    public var resetInfoLeadingPadding: CGFloat {
        switch self {
        case .small: return 0
        case .medium: return 18
        }
    }

    public var resetInfoBottomPadding: CGFloat {
        switch self {
        case .small: return 0
        case .medium: return 11
        }
    }

    public var resetInfoPrimaryFontSize: CGFloat {
        switch self {
        case .small: return 0
        case .medium: return 10
        }
    }

    public var resetInfoSecondaryFontSize: CGFloat {
        switch self {
        case .small: return 0
        case .medium: return 9
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

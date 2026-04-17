import SwiftUI

extension RootView {
    struct RootLayoutContext {
        let geometrySize: CGSize
        let safeAreaInsets: EdgeInsets
        let horizontalSizeClass: UserInterfaceSizeClass?

        var safeAreaTop: CGFloat { safeAreaInsets.top }
        var safeAreaBottom: CGFloat { safeAreaInsets.bottom }
        var safeAreaLeading: CGFloat { safeAreaInsets.leading }
        var safeAreaTrailing: CGFloat { safeAreaInsets.trailing }

        private var isRegularWidth: Bool { horizontalSizeClass == .regular }

        var topBarHorizontalPadding: CGFloat {
            isRegularWidth ? RootLayoutMetrics.topBarHorizontalPaddingRegular : RootLayoutMetrics.topBarHorizontalPaddingCompact
        }

        var topBarMaxWidth: CGFloat? {
            isRegularWidth ? RootLayoutMetrics.topBarMaxWidthRegular : nil
        }

        var regularTopPaddingFallback: CGFloat {
            (isRegularWidth && safeAreaInsets.top <= 0) ? RootLayoutMetrics.regularWidthTopPaddingFallback : 0
        }
    }

    struct RootLayoutSnapshot: Equatable {
        let geometrySize: CGSize
        let safeAreaTop: CGFloat
        let safeAreaBottom: CGFloat
        let safeAreaLeading: CGFloat
        let safeAreaTrailing: CGFloat
        let horizontalSizeClass: UserInterfaceSizeClass?
        let isAuthenticated: Bool
        let isShowingTitleScreen: Bool
        let activeModeIdentifier: GameMode.Identifier
        let topBarHorizontalPadding: CGFloat
        let topBarMaxWidth: CGFloat?
        let regularTopPaddingFallback: CGFloat
        let topBarHeight: CGFloat

        init(
            context: RootLayoutContext,
            isAuthenticated: Bool,
            isShowingTitleScreen: Bool,
            activeMode: GameMode,
            topBarHeight: CGFloat
        ) {
            self.geometrySize = context.geometrySize
            self.safeAreaTop = context.safeAreaTop
            self.safeAreaBottom = context.safeAreaBottom
            self.safeAreaLeading = context.safeAreaLeading
            self.safeAreaTrailing = context.safeAreaTrailing
            self.horizontalSizeClass = context.horizontalSizeClass
            self.isAuthenticated = isAuthenticated
            self.isShowingTitleScreen = isShowingTitleScreen
            self.activeModeIdentifier = activeMode.identifier
            self.topBarHorizontalPadding = context.topBarHorizontalPadding
            self.topBarMaxWidth = context.topBarMaxWidth
            self.regularTopPaddingFallback = context.regularTopPaddingFallback
            self.topBarHeight = topBarHeight
        }

        var horizontalSizeClassDescription: String {
            if let horizontalSizeClass {
                return horizontalSizeClass == .regular ? "regular" : "compact"
            } else {
                return "nil"
            }
        }

        var topBarMaxWidthDescription: String {
            if let width = topBarMaxWidth {
                let rounded = (width * 10).rounded() / 10
                return "\(rounded)"
            } else {
                return "nil"
            }
        }
    }

    enum RootLayoutMetrics {
        static let topBarHorizontalPaddingCompact: CGFloat = 16
        static let topBarHorizontalPaddingRegular: CGFloat = 32
        static let topBarBaseTopPadding: CGFloat = 12
        static let topBarBaseBottomPadding: CGFloat = 10
        static let topBarContentSpacing: CGFloat = 8
        static let topBarMaxWidthRegular: CGFloat = 520
        static let regularWidthTopPaddingFallback: CGFloat = 18
        static let topBarBackgroundOpacity: Double = 0.94
        static let topBarDividerOpacity: Double = 0.45
        static let gamePreparationMinimumDelay: Double = 0.35
    }
}

fileprivate struct TopBarHeightPreferenceKey: PreferenceKey {
    static var defaultValue: CGFloat = 0

    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = nextValue()
    }
}

@MainActor
fileprivate struct TopStatusInsetView: View {
    let context: RootView.RootLayoutContext
    let theme: AppTheme

    private typealias LayoutMetrics = RootView.RootLayoutMetrics

    var body: some View {
        HStack {
            Spacer(minLength: 0)
            if hasVisibleContent {
                VStack(alignment: .leading, spacing: LayoutMetrics.topBarContentSpacing) {
                    statusContent
                }
                .frame(maxWidth: context.topBarMaxWidth ?? .infinity, alignment: .leading)
            }
            Spacer(minLength: 0)
        }
        .allowsHitTesting(false)
        .accessibilityElement(children: .contain)
        .accessibilityLabel(accessibilityMessage)
        .accessibilityHidden(!hasVisibleContent)
        .padding(.horizontal, horizontalPadding)
        .padding(.top, topPadding)
        .padding(.bottom, bottomPadding)
        .background(topBarBackground)
        .overlay(alignment: .bottom) {
            topBarDivider
        }
        .background(
            GeometryReader { proxy in
                Color.clear
                    .preference(key: TopBarHeightPreferenceKey.self, value: proxy.size.height)
            }
        )
    }

    @ViewBuilder
    private var statusContent: some View {
        EmptyView()
    }

    private var accessibilityMessage: LocalizedStringKey {
        ""
    }

    private var hasVisibleContent: Bool {
        false
    }

    private var horizontalPadding: CGFloat {
        hasVisibleContent ? context.topBarHorizontalPadding : 0
    }

    private var topPadding: CGFloat {
        hasVisibleContent ? (LayoutMetrics.topBarBaseTopPadding + context.regularTopPaddingFallback) : 0
    }

    private var bottomPadding: CGFloat {
        hasVisibleContent ? LayoutMetrics.topBarBaseBottomPadding : 0
    }

    @ViewBuilder
    private var topBarBackground: some View {
        if hasVisibleContent {
            theme.backgroundPrimary
                .opacity(LayoutMetrics.topBarBackgroundOpacity)
                .ignoresSafeArea(edges: .top)
        } else {
            Color.clear
        }
    }

    @ViewBuilder
    private var topBarDivider: some View {
        if hasVisibleContent {
            Divider()
                .background(theme.statisticBadgeBorder)
                .opacity(LayoutMetrics.topBarDividerOpacity)
        }
    }
}

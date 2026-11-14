import MizaniShared
import SwiftUI

private enum MizaniTab: String, CaseIterable, Identifiable {
    case home = "Home"
    case activity = "Activity"
    case insights = "Insights"
    case more = "More"

    var id: String { rawValue }

    var symbol: String {
        switch self {
        case .home: "house.fill"
        case .activity: "list.bullet.rectangle"
        case .insights: "chart.bar.xaxis"
        case .more: "ellipsis"
        }
    }
}

private enum MizaniColors {
    static let ink = Color(red: 23.0 / 255.0, green: 53.0 / 255.0, blue: 61.0 / 255.0)
    static let teal = Color(red: 8.0 / 255.0, green: 127.0 / 255.0, blue: 114.0 / 255.0)
    static let muted = Color(red: 73.0 / 255.0, green: 101.0 / 255.0, blue: 105.0 / 255.0)
    static let page = Color(red: 242.0 / 255.0, green: 248.0 / 255.0, blue: 245.0 / 255.0)
    static let card = Color.white.opacity(0.88)
    static let line = Color(red: 222.0 / 255.0, green: 235.0 / 255.0, blue: 230.0 / 255.0)
    static let gold = Color(red: 232.0 / 255.0, green: 191.0 / 255.0, blue: 106.0 / 255.0)
}

struct ContentView: View {
    @State private var selectedTab: MizaniTab = .home
    @State private var isPrivacyStatusPresented = false

    // These shared KMP models are the first common contract used by both clients.
    private let workspaceCurrency = Currency(
        code: "UGX",
        symbol: "USh",
        name: "Ugandan Shilling",
        minorUnits: 0
    )
    private var emptyBalance: Money {
        Money(minorUnits: 0, currencyCode: workspaceCurrency.code)
    }

    var body: some View {
        VStack(spacing: 0) {
            header

            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 22) {
                    pageContent
                    previewStatus
                }
                .frame(maxWidth: 640, alignment: .leading)
                .padding(.horizontal, 20)
                .padding(.top, 16)
                .padding(.bottom, 24)
                .frame(maxWidth: .infinity)
            }

            tabBar
        }
        .background {
            LinearGradient(
                colors: [MizaniColors.page, Color(red: 226.0 / 255.0, green: 244.0 / 255.0, blue: 237.0 / 255.0)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .ignoresSafeArea()
        }
        .preferredColorScheme(.light)
        .sheet(isPresented: $isPrivacyStatusPresented) {
            privacyStatusSheet
                .presentationDetents([.medium])
                .presentationDragIndicator(.visible)
        }
    }

    @ViewBuilder
    private var pageContent: some View {
        switch selectedTab {
        case .home:
            homeContent
        case .activity:
            emptyPage(
                title: "Your activity",
                message: "Transactions will appear here after the iOS data and entry flows are implemented."
            )
        case .insights:
            emptyPage(
                title: "Your insights",
                message: "Mizani will show locally calculated summaries after you have records to review."
            )
        case .more:
            moreContent
        }
    }

    private var header: some View {
        HStack(spacing: 12) {
            ZStack(alignment: .bottom) {
                Circle().fill(MizaniColors.teal)
                Text("M")
                    .font(.system(size: 22, weight: .heavy, design: .rounded))
                    .foregroundStyle(.white)
                    .offset(y: -1)
                Circle()
                    .fill(MizaniColors.gold)
                    .frame(width: 6, height: 6)
                    .offset(y: -8)
            }
            .frame(width: 42, height: 42)
            .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 1) {
                Text("Mizani")
                    .font(.system(size: 18, weight: .bold, design: .rounded))
                    .foregroundStyle(MizaniColors.ink)
                Text("Your money, in balance.")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(MizaniColors.muted)
            }

            Spacer()

            Text("PREVIEW")
                .font(.system(size: 10, weight: .bold, design: .rounded))
                .tracking(0.8)
                .foregroundStyle(MizaniColors.teal)
                .padding(.horizontal, 10)
                .padding(.vertical, 7)
                .background(MizaniColors.teal.opacity(0.09), in: Capsule())
                .accessibilityLabel("iOS preview")
        }
        .padding(.horizontal, 20)
        .padding(.top, 8)
        .padding(.bottom, 12)
    }

    private var homeContent: some View {
        VStack(alignment: .leading, spacing: 20) {
            VStack(alignment: .leading, spacing: 7) {
                Text("Your money,\nin balance.")
                    .font(.system(size: 31, weight: .bold, design: .rounded))
                    .foregroundStyle(MizaniColors.ink)
                    .fixedSize(horizontal: false, vertical: true)
                Text("A private place to organize the financial details you choose to record.")
                    .font(.system(size: 16))
                    .foregroundStyle(MizaniColors.muted)
                    .fixedSize(horizontal: false, vertical: true)
            }

            VStack(alignment: .leading, spacing: 13) {
                HStack {
                    Text("CURRENT VALUE")
                        .font(.system(size: 11, weight: .bold, design: .rounded))
                        .tracking(0.8)
                        .foregroundStyle(MizaniColors.muted)
                    Spacer()
                    Image(systemName: "eye.slash")
                        .foregroundStyle(MizaniColors.teal)
                        .accessibilityLabel("Balance hidden")
                }
                Text("\(workspaceCurrency.code) \(emptyBalance.minorUnits)")
                    .font(.system(size: 28, weight: .bold, design: .rounded))
                    .foregroundStyle(MizaniColors.ink)
                Text("Add a wallet to see your total here.")
                    .font(.system(size: 14))
                    .foregroundStyle(MizaniColors.muted)
            }
            .padding(18)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(MizaniColors.card, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .stroke(MizaniColors.line, lineWidth: 1)
            }

            HStack(spacing: 12) {
                summaryCard(title: "Wallets", value: "None yet", symbol: "wallet.pass.fill")
                summaryCard(title: "Activity", value: "None yet", symbol: "arrow.left.arrow.right")
            }

            VStack(alignment: .leading, spacing: 8) {
                Text("Built around your privacy")
                    .font(.system(size: 16, weight: .semibold, design: .rounded))
                    .foregroundStyle(MizaniColors.ink)
                Text("The Android app keeps financial records on-device. The iOS client is being prepared with the same offline-first design.")
                    .font(.system(size: 14))
                    .foregroundStyle(MizaniColors.muted)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(18)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(MizaniColors.card, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .stroke(MizaniColors.line, lineWidth: 1)
            }
        }
    }

    private func summaryCard(title: String, value: String, symbol: String) -> some View {
        VStack(alignment: .leading, spacing: 13) {
            Image(systemName: symbol)
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(MizaniColors.teal)
                .accessibilityHidden(true)
            Text(title)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(MizaniColors.muted)
            Text(value)
                .font(.system(size: 15, weight: .semibold, design: .rounded))
                .foregroundStyle(MizaniColors.ink)
        }
        .frame(maxWidth: .infinity, minHeight: 90, alignment: .leading)
        .padding(16)
        .background(MizaniColors.card, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .stroke(MizaniColors.line, lineWidth: 1)
        }
    }

    private func emptyPage(title: String, message: String) -> some View {
        VStack(alignment: .leading, spacing: 18) {
            Text(title)
                .font(.system(size: 29, weight: .bold, design: .rounded))
                .foregroundStyle(MizaniColors.ink)

            VStack(alignment: .leading, spacing: 12) {
                Image(systemName: "leaf")
                    .font(.system(size: 24, weight: .medium))
                    .foregroundStyle(MizaniColors.teal)
                    .accessibilityHidden(true)
                Text(message)
                    .font(.system(size: 15))
                    .foregroundStyle(MizaniColors.muted)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(20)
            .frame(maxWidth: .infinity, minHeight: 150, alignment: .leading)
            .background(MizaniColors.card, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .stroke(MizaniColors.line, lineWidth: 1)
            }
        }
    }

    private var moreContent: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("More")
                .font(.system(size: 29, weight: .bold, design: .rounded))
                .foregroundStyle(MizaniColors.ink)

            Button {
                isPrivacyStatusPresented = true
            } label: {
                HStack(spacing: 14) {
                    Image(systemName: "hand.raised.fill")
                        .foregroundStyle(MizaniColors.teal)
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Privacy status")
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(MizaniColors.ink)
                        Text("Read what is and is not implemented in this preview")
                            .font(.system(size: 13))
                            .foregroundStyle(MizaniColors.muted)
                    }
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(MizaniColors.muted)
                }
                .padding(18)
                .background(MizaniColors.card, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: 20, style: .continuous)
                        .stroke(MizaniColors.line, lineWidth: 1)
                }
            }
            .buttonStyle(.plain)
        }
    }

    private var previewStatus: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "hammer.fill")
                .foregroundStyle(MizaniColors.teal)
                .accessibilityHidden(true)
            Text("iOS preview only. Do not enter financial data; secure storage and money-entry flows are not implemented yet.")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(MizaniColors.muted)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.horizontal, 2)
    }

    private var tabBar: some View {
        HStack(spacing: 0) {
            ForEach(MizaniTab.allCases) { tab in
                Button {
                    selectedTab = tab
                } label: {
                    VStack(spacing: 5) {
                        Image(systemName: tab.symbol)
                            .font(.system(size: 17, weight: .semibold))
                        Text(tab.rawValue)
                            .font(.system(size: 10, weight: .semibold))
                    }
                    .foregroundStyle(selectedTab == tab ? MizaniColors.teal : MizaniColors.muted)
                    .frame(maxWidth: .infinity)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(selectedTab == tab ? .isSelected : [])
            }
        }
        .padding(.top, 12)
        .padding(.bottom, 8)
        .background(.regularMaterial)
        .overlay(alignment: .top) {
            Rectangle().fill(MizaniColors.line).frame(height: 1)
        }
    }

    private var privacyStatusSheet: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Privacy status")
                .font(.system(size: 23, weight: .bold, design: .rounded))
                .foregroundStyle(MizaniColors.ink)
            Text("This iOS preview does not save financial records, request permissions, or send network requests. Do not enter financial information. The production iOS app still needs secure local storage, app lock, exports, and a published privacy policy.")
                .font(.system(size: 15))
                .foregroundStyle(MizaniColors.muted)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
        .padding(24)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(MizaniColors.page.ignoresSafeArea())
    }
}

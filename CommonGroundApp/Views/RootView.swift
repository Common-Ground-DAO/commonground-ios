import SwiftUI

struct RootView: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        ZStack {
            BrandBackground()
            switch model.phase {
            case .instance: InstanceOnboardingView()
            case .authentication: AuthenticationView()
            case .home: HomeView()
            }
        }
        .overlay(alignment: .top) {
            if let message = model.errorMessage {
                ErrorBanner(message: message) { model.errorMessage = nil }
                    .padding(.horizontal, 18)
                    .padding(.top, 8)
                    .transition(.move(edge: .top).combined(with: .opacity))
            }
        }
        .animation(.spring(response: 0.35), value: model.errorMessage)
        .task { await model.restoreOnLaunch() }
    }
}

struct BrandBackground: View {
    var body: some View {
        AppTheme.background
        .ignoresSafeArea()
        .overlay(alignment: .topTrailing) {
            Circle()
                .fill(AppTheme.accent.opacity(0.14))
                .frame(width: 360, height: 360)
                .blur(radius: 8)
                .offset(x: 140, y: -170)
        }
    }
}

struct ErrorBanner: View {
    let message: String
    let dismiss: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.orange)
            Text(message).font(.subheadline).frame(maxWidth: .infinity, alignment: .leading)
            Button(action: dismiss) { Image(systemName: "xmark") }
        }
        .padding(14)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16))
    }
}

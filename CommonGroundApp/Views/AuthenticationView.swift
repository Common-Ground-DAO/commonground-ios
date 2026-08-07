import CommonGroundKit
import SwiftUI

struct AuthenticationView: View {
    @EnvironmentObject private var model: AppModel
    @State private var mode = 0
    @State private var alias = ""
    @State private var email = ""
    @State private var displayName = ""
    @State private var password = ""

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                HStack {
                    Button(action: model.chooseAnotherInstance) {
                        Label("Instances", systemImage: "chevron.left")
                    }
                    Spacer()
                    Label(model.instanceHost, systemImage: "network")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                }

                VStack(alignment: .leading, spacing: 6) {
                    Text("Welcome in")
                        .font(.system(size: 36, weight: .bold, design: .rounded))
                    if let provider = model.instanceConfig?.captchaProvider {
                        Text(capabilityText(provider))
                            .foregroundStyle(.secondary)
                    }
                }

                if model.savedDeviceID != nil {
                    Button { Task { await model.continueWithDevice() } } label: {
                        Label("Continue securely on this device", systemImage: "faceid")
                            .frame(maxWidth: .infinity)
                            .padding(15)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.orange)
                }

                Picker("Account action", selection: $mode) {
                    Text("Sign in").tag(0)
                    Text("Create account").tag(1)
                }
                .pickerStyle(.segmented)

                VStack(spacing: 14) {
                    if mode == 0 {
                        Field(title: "EMAIL OR PROFILE NAME", placeholder: "you@example.org", text: $alias)
                    } else {
                        Field(title: "EMAIL", placeholder: "you@example.org", text: $email, keyboard: .emailAddress)
                        Field(title: "PROFILE NAME", placeholder: "your_name", text: $displayName)
                    }
                    SecureField("Password", text: $password)
                        .textContentType(mode == 0 ? .password : .newPassword)
                        .padding(15)
                        .background(Color.white.opacity(0.075), in: RoundedRectangle(cornerRadius: 14))
                }

                Button(action: submit) {
                    HStack {
                        if model.isWorking { ProgressView().tint(.black) }
                        Text(model.isWorking ? model.activity : (mode == 0 ? "Sign in" : "Create account"))
                        Spacer()
                        Image(systemName: mode == 0 ? "arrow.right" : "person.badge.plus")
                    }
                    .fontWeight(.semibold)
                    .padding(16)
                    .foregroundStyle(.black)
                    .background(.orange, in: RoundedRectangle(cornerRadius: 15))
                }
                .disabled(model.isWorking || password.isEmpty || (mode == 0 ? alias.isEmpty : email.isEmpty || displayName.isEmpty))
            }
            .frame(maxWidth: 560)
            .padding(26)
            .frame(maxWidth: .infinity)
        }
    }

    private func submit() {
        Task {
            if mode == 0 { await model.signIn(alias: alias, password: password) }
            else { await model.register(email: email, password: password, displayName: displayName) }
        }
    }

    private func capabilityText(_ provider: CaptchaProvider) -> String {
        switch provider {
        case .altcha: return "Private, native proof-of-work protects registration."
        case .off: return "This development instance has registration protection disabled."
        case .recaptcha: return "Sign-in is available; registration uses this instance’s web flow."
        }
    }
}

private struct Field: View {
    let title: String
    let placeholder: String
    @Binding var text: String
    var keyboard: UIKeyboardType = .default

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            Text(title).font(.caption2.weight(.bold)).foregroundStyle(.secondary)
            TextField(placeholder, text: $text)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .keyboardType(keyboard)
        }
        .padding(15)
        .background(Color.white.opacity(0.075), in: RoundedRectangle(cornerRadius: 14))
    }
}

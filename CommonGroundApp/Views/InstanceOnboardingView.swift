import SwiftUI

struct InstanceOnboardingView: View {
    @EnvironmentObject private var model: AppModel
    @FocusState private var focused: Bool

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 28) {
                Spacer(minLength: 54)
                VStack(alignment: .leading, spacing: 12) {
                    Image(systemName: "circle.hexagongrid.fill")
                        .font(.system(size: 48, weight: .semibold))
                        .foregroundStyle(.orange)
                        .accessibilityHidden(true)
                    Text("Find common ground.")
                        .font(.largeTitle.bold())
                        .fontDesign(.rounded)
                    Text("Communities belong to many independent instances. Choose yours to begin.")
                        .font(.title3)
                        .foregroundStyle(.primary)
                }

                VStack(alignment: .leading, spacing: 12) {
                    Text("INSTANCE ADDRESS")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(.secondary)
                    TextField("community.example", text: $model.instanceInput)
                        .accessibilityIdentifier("instance.address")
                        .textInputAutocapitalization(.never)
                        .keyboardType(.URL)
                        .autocorrectionDisabled()
                        .focused($focused)
                        .submitLabel(.go)
                        .onSubmit { Task { await model.connect() } }
                        .frame(minHeight: 28)
                        .padding(16)
                        .background(Color.white.opacity(0.075), in: RoundedRectangle(cornerRadius: 15))
                    Button { Task { await model.connect() } } label: {
                        HStack {
                            if model.isWorking { ProgressView().tint(.black) }
                            Text(model.isWorking ? model.activity : "Continue")
                            Spacer()
                            Image(systemName: "arrow.right")
                        }
                        .fontWeight(.semibold)
                        .padding(16)
                        .foregroundStyle(.black)
                        .background(.orange, in: RoundedRectangle(cornerRadius: 15))
                    }
                    .disabled(model.isWorking)
                    .accessibilityIdentifier("instance.continue")
                }

                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Image(systemName: "lock.shield")
                        .accessibilityHidden(true)
                    Text("Your account and session stay isolated to the instance you select.")
                        .fixedSize(horizontal: false, vertical: true)
                }
                .font(.footnote)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .accessibilityElement(children: .combine)
            }
            .frame(maxWidth: 560)
            .padding(26)
            .frame(maxWidth: .infinity)
        }
    }
}

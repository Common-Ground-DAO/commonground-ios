import CommonGroundKit
import SwiftUI

struct HomeView: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        HomeContent(store: model.store)
    }
}

private struct HomeContent: View {
    @EnvironmentObject private var model: AppModel
    @ObservedObject var store: SyncStore
    @State private var showAccount = false

    private var communities: [Community] {
        store.communities.values.sorted { $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending }
    }

    private var selectedChannel: Channel? {
        communities.flatMap(\.channels).first { $0.channelId == model.selectedChannelID }
    }

    var body: some View {
        NavigationSplitView {
            List(selection: $model.selectedChannelID) {
                Section {
                    Button { showAccount = true } label: {
                        HStack(spacing: 12) {
                            Avatar(name: store.ownUser?.displayName ?? "CG")
                            VStack(alignment: .leading, spacing: 2) {
                                Text(store.ownUser?.displayName ?? "Member").fontWeight(.semibold)
                                Text(model.instanceHost).font(.caption).foregroundStyle(.secondary)
                            }
                        }
                    }
                    .buttonStyle(.plain)
                }

                ForEach(communities) { community in
                    Section(community.title.uppercased()) {
                        ForEach(community.channels.sorted(by: { $0.order < $1.order })) { channel in
                            Label(channel.title, systemImage: "number")
                                .tag(channel.channelId)
                        }
                    }
                }
            }
            .scrollContentBackground(.hidden)
            .background(Color.black.opacity(0.12))
            .navigationTitle("Common Ground")
        } detail: {
            if let channel = selectedChannel {
                ChannelView(channel: channel, store: store)
            } else {
                VStack(spacing: 12) {
                    Image(systemName: "bubble.left.and.bubble.right")
                        .font(.system(size: 38))
                        .foregroundStyle(.orange)
                    Text("Choose a conversation").font(.title3.bold())
                    Text("Your communities and channels appear in the sidebar.")
                        .foregroundStyle(.secondary)
                }
            }
        }
        .sheet(isPresented: $showAccount) {
            AccountView(store: store)
                .presentationDetents([.medium])
        }
        .overlay(alignment: .top) {
            if let notice = model.realtimeNotice {
                Label(notice, systemImage: "bolt.slash")
                    .font(.caption)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(.ultraThinMaterial, in: Capsule())
                    .padding(.top, 8)
            }
        }
    }
}

private struct ChannelView: View {
    @EnvironmentObject private var model: AppModel
    let channel: Channel
    @ObservedObject var store: SyncStore

    private var messages: [Message] { store.orderedMessages(channelId: channel.channelId) }

    var body: some View {
        VStack(spacing: 0) {
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 18) {
                        if messages.isEmpty {
                            VStack(spacing: 10) {
                                Image(systemName: "sparkles").font(.title).foregroundStyle(.orange)
                                Text("This is the beginning of #\(channel.title).")
                                    .font(.headline)
                            }
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 70)
                        }
                        ForEach(messages) { message in
                            MessageRow(message: message, isOwn: message.creatorId == store.ownUser?.id)
                                .id(message.id)
                        }
                    }
                    .padding(20)
                }
                .refreshable { await model.loadMessages(channel: channel) }
                .onChange(of: messages.count) { _ in
                    if let id = messages.last?.id { withAnimation { proxy.scrollTo(id, anchor: .bottom) } }
                }
            }

            Divider().opacity(0.5)
            HStack(alignment: .bottom, spacing: 10) {
                TextField("Message #\(channel.title)", text: $model.draftMessage, axis: .vertical)
                    .lineLimit(1...5)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 11)
                    .background(Color.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 18))
                Button { Task { await model.sendMessage(channel: channel) } } label: {
                    Image(systemName: "arrow.up")
                        .fontWeight(.bold)
                        .frame(width: 42, height: 42)
                        .foregroundStyle(.black)
                        .background(.orange, in: Circle())
                }
                .disabled(model.draftMessage.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
            .padding(12)
        }
        .navigationTitle(channel.title)
        .navigationBarTitleDisplayMode(.inline)
        .task(id: channel.channelId) { await model.loadMessages(channel: channel) }
    }
}

private struct MessageRow: View {
    let message: Message
    let isOwn: Bool

    var body: some View {
        HStack(alignment: .top, spacing: 11) {
            Avatar(name: isOwn ? "You" : String(message.creatorId.prefix(4)), small: true)
            VStack(alignment: .leading, spacing: 5) {
                HStack {
                    Text(isOwn ? "You" : "Member")
                        .font(.subheadline.weight(.semibold))
                    Text(relativeDate(message.createdAt))
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
                Text(message.body.plainText)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    private func relativeDate(_ value: String) -> String {
        guard let date = ISO8601DateFormatter().date(from: value) else { return "" }
        return date.formatted(date: .omitted, time: .shortened)
    }
}

private struct AccountView: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.dismiss) private var dismiss
    @ObservedObject var store: SyncStore

    var body: some View {
        NavigationStack {
            VStack(spacing: 20) {
                Avatar(name: store.ownUser?.displayName ?? "CG")
                    .scaleEffect(1.6)
                    .padding(20)
                Text(store.ownUser?.displayName ?? "Member").font(.title2.bold())
                Text(store.ownUser?.email ?? model.instanceHost).foregroundStyle(.secondary)
                Spacer()
                Button(role: .destructive) {
                    dismiss()
                    Task { await model.logout() }
                } label: {
                    Label("Log out and remove this device", systemImage: "rectangle.portrait.and.arrow.right")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
            }
            .padding(24)
            .navigationTitle("Account")
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
        }
    }
}

private struct Avatar: View {
    let name: String
    var small = false

    var body: some View {
        Text(String(name.prefix(2)).uppercased())
            .font(small ? .caption.bold() : .subheadline.bold())
            .frame(width: small ? 34 : 42, height: small ? 34 : 42)
            .foregroundStyle(.black)
            .background(
                LinearGradient(colors: [.orange, .yellow], startPoint: .topLeading, endPoint: .bottomTrailing),
                in: Circle()
            )
    }
}

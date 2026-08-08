import CSQLite
import Foundation

public struct OfflineSnapshot: Sendable {
    public let ownUser: OwnUser?
    public let communities: [Community]
    public let chats: [Chat]
    public let messages: [Message]
    public let notifications: [AppNotification]
    public let users: [UserProfile]
    public let pendingMessages: [PendingMessage]
    public let savedMessageIDs: Set<String>
    public let unreadNotificationCount: Int
}

public enum OfflineDatabaseError: Error, LocalizedError {
    case open(String)
    case statement(String)
    case execute(String)

    public var errorDescription: String? {
        switch self {
        case .open(let message): "Could not open the offline database: \(message)"
        case .statement(let message): "Could not prepare the offline database: \(message)"
        case .execute(let message): "Could not update the offline database: \(message)"
        }
    }
}

/// A deliberately small SQLite persistence boundary. Domain values stay Codable,
/// while SQLite supplies atomic updates, indexing, migrations, and account scoping.
/// This keeps the transport/models independent from any UI persistence framework.
public actor OfflineDatabase {
    private let connection: OpaquePointer
    private let scope: String
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()
    private static let transient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)

    public init(fileURL: URL, scope: String) throws {
        try FileManager.default.createDirectory(
            at: fileURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        var database: OpaquePointer?
        guard sqlite3_open_v2(
            fileURL.path,
            &database,
            SQLITE_OPEN_CREATE | SQLITE_OPEN_READWRITE | SQLITE_OPEN_FULLMUTEX,
            nil
        ) == SQLITE_OK, let database else {
            let message = database.map { String(cString: sqlite3_errmsg($0)) } ?? "unknown error"
            if let database { sqlite3_close(database) }
            throw OfflineDatabaseError.open(message)
        }
        connection = database
        self.scope = scope
        do {
            try Self.execute(
                connection,
                sql: """
                PRAGMA journal_mode = WAL;
                PRAGMA foreign_keys = ON;
                PRAGMA synchronous = NORMAL;
                CREATE TABLE IF NOT EXISTS records (
                    scope TEXT NOT NULL,
                    kind TEXT NOT NULL,
                    id TEXT NOT NULL,
                    parent_id TEXT,
                    payload BLOB NOT NULL,
                    updated_at REAL NOT NULL,
                    PRIMARY KEY (scope, kind, id)
                );
                CREATE INDEX IF NOT EXISTS records_parent
                    ON records(scope, kind, parent_id);
                CREATE TABLE IF NOT EXISTS state (
                    scope TEXT NOT NULL,
                    key TEXT NOT NULL,
                    value TEXT NOT NULL,
                    PRIMARY KEY (scope, key)
                );
                CREATE TABLE IF NOT EXISTS drafts (
                    scope TEXT NOT NULL,
                    conversation_id TEXT NOT NULL,
                    text TEXT NOT NULL,
                    updated_at REAL NOT NULL,
                    PRIMARY KEY (scope, conversation_id)
                );
                PRAGMA user_version = 1;
                """
            )
            try? FileManager.default.setAttributes(
                [.protectionKey: FileProtectionType.completeUntilFirstUserAuthentication],
                ofItemAtPath: fileURL.path
            )
        } catch {
            sqlite3_close(database)
            throw error
        }
    }

    deinit { sqlite3_close(connection) }

    public static func defaultURL(instance: InstanceURL, userID: String) throws -> URL {
        guard let root = FileManager.default.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        ).first else { throw OfflineDatabaseError.open("Application Support is unavailable") }
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-_."))
        func safe(_ value: String) -> String {
            value.unicodeScalars.map { allowed.contains($0) ? String($0) : "_" }.joined()
        }
        let host = instance.url.host ?? "instance"
        return root
            .appending(path: "CommonGround", directoryHint: .isDirectory)
            .appending(path: safe(host), directoryHint: .isDirectory)
            .appending(path: "\(safe(userID)).sqlite3")
    }

    public func loadSnapshot() throws -> OfflineSnapshot {
        OfflineSnapshot(
            ownUser: try load(kind: "ownUser", as: OwnUser.self).first,
            communities: try load(kind: "community", as: Community.self),
            chats: try load(kind: "chat", as: Chat.self),
            messages: try load(kind: "message", as: Message.self),
            notifications: try load(kind: "notification", as: AppNotification.self),
            users: try load(kind: "user", as: UserProfile.self),
            pendingMessages: try load(kind: "pendingMessage", as: PendingMessage.self),
            savedMessageIDs: Set(try load(kind: "savedMessage", as: String.self)),
            unreadNotificationCount: Int(try stateValue(for: "unreadNotificationCount") ?? "0") ?? 0
        )
    }

    public func replaceAccountState(_ response: LoginResponse) throws {
        try transaction {
            try delete(kind: "ownUser")
            try delete(kind: "community")
            try delete(kind: "chat")
            try upsert(kind: "ownUser", id: response.ownData.id, value: response.ownData)
            for community in response.communities {
                try upsert(kind: "community", id: community.id, value: community)
            }
            for chat in response.chats { try upsert(kind: "chat", id: chat.id, value: chat) }
            try setState(String(response.unreadNotificationCount), for: "unreadNotificationCount")
        }
    }

    public func save(community: Community) throws {
        try upsert(kind: "community", id: community.id, value: community)
    }

    public func save(ownUser: OwnUser) throws {
        try upsert(kind: "ownUser", id: ownUser.id, value: ownUser)
    }

    public func removeCommunity(id: String) throws { try remove(kind: "community", id: id) }

    public func save(chat: Chat) throws { try upsert(kind: "chat", id: chat.id, value: chat) }
    public func removeChat(id: String) throws { try remove(kind: "chat", id: id) }

    public func save(messages: [Message]) throws {
        try transaction {
            for message in messages {
                try upsert(
                    kind: "message",
                    id: message.id,
                    parentID: message.channelId,
                    value: message
                )
            }
        }
    }

    public func removeMessage(id: String) throws { try remove(kind: "message", id: id) }

    public func save(pendingMessage: PendingMessage) throws {
        try upsert(
            kind: "pendingMessage",
            id: pendingMessage.id,
            parentID: pendingMessage.access.channelId,
            value: pendingMessage
        )
    }

    public func removePendingMessage(id: String) throws {
        try remove(kind: "pendingMessage", id: id)
    }

    public func setMessageSaved(id: String, saved: Bool) throws {
        if saved { try upsert(kind: "savedMessage", id: id, value: id) }
        else { try remove(kind: "savedMessage", id: id) }
    }

    public func save(users: [UserProfile]) throws {
        try transaction {
            for user in users { try upsert(kind: "user", id: user.id, value: user) }
        }
    }

    public func replaceNotifications(_ values: [AppNotification], unreadCount: Int) throws {
        try transaction {
            try delete(kind: "notification")
            for value in values { try upsert(kind: "notification", id: value.id, value: value) }
            try setState(String(unreadCount), for: "unreadNotificationCount")
        }
    }

    public func save(notification: AppNotification, unreadCount: Int) throws {
        try transaction {
            try upsert(kind: "notification", id: notification.id, value: notification)
            try setState(String(unreadCount), for: "unreadNotificationCount")
        }
    }

    public func saveDraft(_ text: String, conversationID: String) throws {
        if text.isEmpty {
            try execute(
                "DELETE FROM drafts WHERE scope = ? AND conversation_id = ?",
                bindings: [.text(scope), .text(conversationID)]
            )
            return
        }
        try execute(
            """
            INSERT INTO drafts(scope, conversation_id, text, updated_at) VALUES(?, ?, ?, ?)
            ON CONFLICT(scope, conversation_id) DO UPDATE SET
                text = excluded.text, updated_at = excluded.updated_at
            """,
            bindings: [.text(scope), .text(conversationID), .text(text), .double(Date().timeIntervalSince1970)]
        )
    }

    public func draft(conversationID: String) throws -> String? {
        try scalar(
            "SELECT text FROM drafts WHERE scope = ? AND conversation_id = ?",
            bindings: [.text(scope), .text(conversationID)]
        )
    }

    public func clear() throws {
        try transaction {
            for table in ["records", "state", "drafts"] {
                try execute("DELETE FROM \(table) WHERE scope = ?", bindings: [.text(scope)])
            }
        }
    }

    private enum Binding { case text(String), data(Data), double(Double) }

    private func upsert<Value: Encodable>(
        kind: String,
        id: String,
        parentID: String? = nil,
        value: Value
    ) throws {
        let data = try encoder.encode(value)
        var bindings: [Binding] = [.text(scope), .text(kind), .text(id)]
        bindings.append(parentID.map(Binding.text) ?? .text(""))
        bindings.append(.data(data))
        bindings.append(.double(Date().timeIntervalSince1970))
        try execute(
            """
            INSERT INTO records(scope, kind, id, parent_id, payload, updated_at)
            VALUES(?, ?, ?, NULLIF(?, ''), ?, ?)
            ON CONFLICT(scope, kind, id) DO UPDATE SET
                parent_id = excluded.parent_id,
                payload = excluded.payload,
                updated_at = excluded.updated_at
            """,
            bindings: bindings
        )
    }

    private func load<Value: Decodable>(kind: String, as type: Value.Type) throws -> [Value] {
        let statement = try prepare(
            "SELECT payload FROM records WHERE scope = ? AND kind = ? ORDER BY updated_at ASC"
        )
        defer { sqlite3_finalize(statement) }
        try bind([.text(scope), .text(kind)], to: statement)
        var values: [Value] = []
        while sqlite3_step(statement) == SQLITE_ROW {
            guard let bytes = sqlite3_column_blob(statement, 0) else { continue }
            let count = Int(sqlite3_column_bytes(statement, 0))
            values.append(try decoder.decode(Value.self, from: Data(bytes: bytes, count: count)))
        }
        return values
    }

    private func remove(kind: String, id: String) throws {
        try execute(
            "DELETE FROM records WHERE scope = ? AND kind = ? AND id = ?",
            bindings: [.text(scope), .text(kind), .text(id)]
        )
    }

    private func delete(kind: String) throws {
        try execute(
            "DELETE FROM records WHERE scope = ? AND kind = ?",
            bindings: [.text(scope), .text(kind)]
        )
    }

    private func setState(_ value: String, for key: String) throws {
        try execute(
            """
            INSERT INTO state(scope, key, value) VALUES(?, ?, ?)
            ON CONFLICT(scope, key) DO UPDATE SET value = excluded.value
            """,
            bindings: [.text(scope), .text(key), .text(value)]
        )
    }

    private func stateValue(for key: String) throws -> String? {
        try scalar(
            "SELECT value FROM state WHERE scope = ? AND key = ?",
            bindings: [.text(scope), .text(key)]
        )
    }

    private func scalar(_ sql: String, bindings: [Binding]) throws -> String? {
        let statement = try prepare(sql)
        defer { sqlite3_finalize(statement) }
        try bind(bindings, to: statement)
        guard sqlite3_step(statement) == SQLITE_ROW,
              let value = sqlite3_column_text(statement, 0) else { return nil }
        return String(cString: value)
    }

    private func transaction(_ work: () throws -> Void) throws {
        try Self.execute(connection, sql: "BEGIN IMMEDIATE")
        do {
            try work()
            try Self.execute(connection, sql: "COMMIT")
        } catch {
            try? Self.execute(connection, sql: "ROLLBACK")
            throw error
        }
    }

    private func execute(_ sql: String, bindings: [Binding] = []) throws {
        let statement = try prepare(sql)
        defer { sqlite3_finalize(statement) }
        try bind(bindings, to: statement)
        guard sqlite3_step(statement) == SQLITE_DONE else {
            throw OfflineDatabaseError.execute(String(cString: sqlite3_errmsg(connection)))
        }
    }

    private func prepare(_ sql: String) throws -> OpaquePointer {
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(connection, sql, -1, &statement, nil) == SQLITE_OK,
              let statement else {
            throw OfflineDatabaseError.statement(String(cString: sqlite3_errmsg(connection)))
        }
        return statement
    }

    private func bind(_ bindings: [Binding], to statement: OpaquePointer) throws {
        for (offset, value) in bindings.enumerated() {
            let index = Int32(offset + 1)
            let result: Int32
            switch value {
            case .text(let text):
                result = sqlite3_bind_text(statement, index, text, -1, Self.transient)
            case .data(let data):
                result = data.withUnsafeBytes { bytes in
                    sqlite3_bind_blob(statement, index, bytes.baseAddress, Int32(data.count), Self.transient)
                }
            case .double(let value):
                result = sqlite3_bind_double(statement, index, value)
            }
            guard result == SQLITE_OK else {
                throw OfflineDatabaseError.execute(String(cString: sqlite3_errmsg(connection)))
            }
        }
    }

    private static func execute(_ database: OpaquePointer, sql: String) throws {
        var message: UnsafeMutablePointer<CChar>?
        guard sqlite3_exec(database, sql, nil, nil, &message) == SQLITE_OK else {
            let value = message.map { String(cString: $0) }
                ?? String(cString: sqlite3_errmsg(database))
            sqlite3_free(message)
            throw OfflineDatabaseError.execute(value)
        }
    }
}

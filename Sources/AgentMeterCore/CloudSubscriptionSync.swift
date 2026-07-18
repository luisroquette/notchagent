import CloudKit
import Foundation

public enum CloudSyncState: Equatable, Sendable {
    case localOnly
    case syncing
    case synced(Date)
    case waitingToRetry(Date)
    case unavailable
    case failed
}

@MainActor
public final class CloudSubscriptionSync {
    private let container: CKContainer
    private let recordID = CKRecord.ID(recordName: "subscription-wallet-v1")
    private let recordType = "AgentMeterWallet"

    public init(containerIdentifier: String = "iCloud.br.com.lfrprojects.agentmeter") {
        container = CKContainer(identifier: containerIdentifier)
    }

    public func synchronize(_ local: SubscriptionSyncSnapshot) async throws -> SubscriptionSyncSnapshot {
        guard try await container.accountStatus() == .available else {
            throw CloudSyncFailure.accountUnavailable
        }

        let database = container.privateCloudDatabase
        var candidate = local

        for attempt in 0..<2 {
            let remoteRecord = try await fetchRecord(from: database)
            let remote = try snapshot(from: remoteRecord)
            let merged = candidate.merged(with: remote)
            do {
                try await save(merged, existingRecord: remoteRecord, to: database)
                return merged
            } catch let error as CKError where error.code == .serverRecordChanged && attempt == 0 {
                if let serverRecord = error.userInfo[CKRecordChangedErrorServerRecordKey] as? CKRecord {
                    candidate = merged.merged(with: try snapshot(from: serverRecord))
                    continue
                }
                throw error
            }
        }

        return candidate
    }

    private func fetchRecord(from database: CKDatabase) async throws -> CKRecord? {
        do {
            return try await database.record(for: recordID)
        } catch let error as CKError where error.code == .unknownItem {
            return nil
        }
    }

    private func snapshot(from record: CKRecord?) throws -> SubscriptionSyncSnapshot {
        guard let data = record?["payload"] as? Data else {
            return SubscriptionSyncSnapshot(subscriptions: [])
        }
        return try JSONDecoder().decode(SubscriptionSyncSnapshot.self, from: data)
    }

    private func save(_ snapshot: SubscriptionSyncSnapshot, existingRecord: CKRecord?, to database: CKDatabase) async throws {
        let record = existingRecord ?? CKRecord(recordType: recordType, recordID: recordID)
        record["payload"] = try JSONEncoder().encode(snapshot) as CKRecordValue
        record["updatedAt"] = Date() as CKRecordValue
        _ = try await database.save(record)
    }
}

public enum CloudSyncFailure: Error {
    case accountUnavailable
}

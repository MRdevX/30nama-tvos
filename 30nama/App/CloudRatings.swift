import CloudKit

/// The ratings as one record in the user's private iCloud database.
actor CloudRatings: RatingCloud {
    private let container = CKContainer.default()
    private let recordID: CKRecord.ID
    /// The record as last seen, which a save has to be built on for iCloud to accept it.
    private var seen: CKRecord?

    /// - Parameter recordName: the record to keep the book in. Only a trial run needs one of its own.
    init(recordName: String = "ratings") {
        recordID = CKRecord.ID(recordName: recordName)
    }

    func load() async throws -> (data: Data, tag: String)? {
        guard try await container.accountStatus() == .available else { throw RatingCloudError.unavailable }
        do {
            let record = try await container.privateCloudDatabase.record(for: recordID)
            seen = record
            return (record["book"] as? Data ?? Data(), record.recordChangeTag ?? "")
        } catch let error as CKError where error.code == .unknownItem {
            seen = nil
            return nil
        }
    }

    func save(_ data: Data, replacing tag: String?) async throws {
        let record: CKRecord
        if let tag {
            guard let seen, seen.recordChangeTag == tag else { throw RatingCloudError.changed }
            record = seen
        } else {
            record = CKRecord(recordType: "Ratings", recordID: recordID)
        }
        record["book"] = data as NSData
        do {
            // Saving is refused when the record on the server is newer than the one this is built on.
            seen = try await container.privateCloudDatabase.save(record)
        } catch let error as CKError where error.code == .serverRecordChanged {
            throw RatingCloudError.changed
        }
    }
}

public struct ReqlGlobalOpts : ReqlOpts {
    public let useOutdated: Bool?
    public let timeFormat: ReqlFormat?
    public let profile: Bool?
    public let durability: ReqlDurability?
    public let groupFormat: ReqlFormat?
    public let noreply: Bool?
    public let db: String?
    public let arrayLimit: Int?
    public let binaryFormat: ReqlFormat?
    public let minBatchRows: Int?
    public let maxBatchRows: Int?
    public let maxBatchBytes: Int?
    public let maxBatchSeconds: Int?
    public let firstBatchScaledownFactor: Double?
    
    public init(useOutdated: Bool? = nil,
                timeFormat: ReqlFormat? = nil,
                profile: Bool? = nil,
                durability: ReqlDurability? = nil,
                groupFormat: ReqlFormat? = nil,
                noreply: Bool? = nil,
                db: String? = nil,
                arrayLimit: Int? = nil,
                binaryFormat: ReqlFormat? = nil,
                minBatchRows: Int? = nil,
                maxBatchRows: Int? = nil,
                maxBatchBytes: Int? = nil,
                maxBatchSeconds: Int? = nil,
                firstBatchScaledownFactor: Double? = nil) {
        self.useOutdated = useOutdated
        self.timeFormat = timeFormat
        self.profile = profile
        self.durability = durability
        self.groupFormat = groupFormat
        self.noreply = noreply
        self.db = db
        self.arrayLimit = arrayLimit
        self.binaryFormat = binaryFormat
        self.minBatchRows = minBatchRows
        self.maxBatchRows = maxBatchRows
        self.maxBatchBytes = maxBatchBytes
        self.maxBatchSeconds = maxBatchSeconds
        self.firstBatchScaledownFactor = firstBatchScaledownFactor
    }
    
    public var rawValue: [String : Any] {
        var opts: [String: Any] = [:]
        if let useOutdated = self.useOutdated {
            opts["use_outdated"] = useOutdated
        }
        if let timeFormat = self.timeFormat {
            opts["time_format"] = timeFormat.rawValue
        }
        if let profile = self.profile {
            opts["profile"] = profile
        }
        if let durability = self.durability {
            opts["durability"] = durability.rawValue
        }
        if let groupFormat = self.groupFormat {
            opts["group_format"] = groupFormat.rawValue
        }
        if let noreply = self.noreply {
            opts["noreply"] = noreply
        }
        if let db = self.db {
            opts["db"] = db
        }
        if let arrayLimit = self.arrayLimit {
            opts["array_limit"] = arrayLimit
        }
        if let binaryFormat = self.binaryFormat {
            opts["binary_format"] = binaryFormat.rawValue
        }
        if let minBatchRows = self.minBatchRows {
            opts["min_batch_rows"] = minBatchRows
        }
        if let maxBatchRows = self.maxBatchRows {
            opts["max_batch_Rows"] = maxBatchRows
        }
        if let maxBatchBytes = self.maxBatchBytes {
            opts["max_batch_bytes"] = maxBatchBytes
        }
        if let maxBatchSeconds = self.maxBatchSeconds {
            opts["max_batch_seconds"] = maxBatchSeconds
        }
        if let firstBatchScaledownFactor = self.firstBatchScaledownFactor {
            opts["first_batch_scaledown_factor"] = firstBatchScaledownFactor
        }
        return opts
    }
    
}

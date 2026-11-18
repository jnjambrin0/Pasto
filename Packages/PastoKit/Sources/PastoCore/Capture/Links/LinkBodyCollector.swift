import Foundation

/// The body of a link download as it arrives, whichever way it comes: kept up to the plan's
/// byte limit — cut there for a page, refused whole for an image — and finished as soon as a
/// page's `</head>` (and a title) is in when the plan says so (`HTMLHeadScanner.isFinished`).
struct LinkBodyCollector {
    enum Step: Equatable {
        /// Keep receiving.
        case more
        /// Enough has arrived: stop the transfer and use what there is.
        case done
        /// Over the limit of a body that is no use cut: stop and give up.
        case tooLarge
    }

    let plan: LinkDownloadPlan
    private(set) var data = Data()
    /// Whether the body went on past what was kept.
    private(set) var isTruncated = false
    private var head: HTMLHeadScanner?

    /// `expectedLength` is the length the response declares, or -1.
    init(plan: LinkDownloadPlan, expectedLength: Int64) {
        self.plan = plan
        if plan.endsWithHead {
            head = HTMLHeadScanner()
        }
        if expectedLength > 0 {
            data.reserveCapacity(Int(min(expectedLength, Int64(plan.byteLimit))))
        }
    }

    /// Adds the next part of the body and says whether to go on.
    mutating func append(_ chunk: Data) -> Step {
        let room = plan.byteLimit - data.count
        guard chunk.count <= room else {
            guard plan.keepsPrefix else { return .tooLarge }
            data.append(chunk.prefix(room))
            isTruncated = true
            return .done
        }
        data.append(chunk)
        if var scanner = head {
            data.withUnsafeBytes { scanner.scan($0, isComplete: false) }
            head = scanner
            if scanner.isFinished {
                return .done
            }
        }
        return .more
    }
}

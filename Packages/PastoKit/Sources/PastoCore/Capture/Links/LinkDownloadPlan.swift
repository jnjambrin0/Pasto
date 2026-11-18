/// How much of a response a link download keeps, decided once its headers are in.
struct LinkDownloadPlan: Sendable, Equatable {
    /// At most this many bytes of the body, decoded, are received. Zero keeps the headers only.
    var byteLimit: Int
    /// Past the limit, keep the first `byteLimit` bytes (a page: what matters is at its start);
    /// otherwise the download fails (an image: a part of one is no use).
    var keepsPrefix: Bool
    /// Stop as soon as the page's `</head>` is in.
    var endsWithHead = false
}

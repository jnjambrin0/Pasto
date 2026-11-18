import Darwin
import Foundation

/// A classic Mac OS alias record (version 2), which is how a `.DS_Store` points at the picture
/// behind a folder's icons (`icvp` → `backgroundImageAlias`).
///
/// The layout follows the public descriptions of the format (the `mac_alias` notes, Apple's old
/// `Aliases.h`) and matches the records that Finder and other DMG tools write: a fixed 150-byte
/// part with the volume and the file in Pascal strings, catalog node IDs and HFS dates, then tagged
/// extra fields (Unicode names, POSIX paths), each padded to an even length, ending with tag -1.
struct FinderAlias: Equatable {
    var volumeName: String
    /// Seconds since 1904-01-01, as HFS counts.
    var volumeDate: UInt32
    var parentName: String
    var parentID: UInt32
    var fileName: String
    var fileID: UInt32
    var fileDate: UInt32
    /// The file's path from the volume's root, starting with "/".
    var posixPath: String
    /// Where the volume is expected to be mounted, "/Volumes/<name>".
    var mountPoint: String

    /// Seconds between 1904-01-01 (HFS) and 1970-01-01 (Unix).
    static let hfsEpochOffset: TimeInterval = 2_082_844_800

    static func hfsDate(_ date: Date) -> UInt32 {
        UInt32(clamping: Int64((date.timeIntervalSince1970 + hfsEpochOffset).rounded(.down)))
    }

    /// An alias to `file`, which must be on the HFS+ volume mounted at `volume`, one level deep
    /// (`.background/background.tiff`). Node IDs come from the mounted file system; the mount point
    /// written is `/Volumes/<volume name>`, where the user's Mac will mount it.
    static func make(file: URL, volume: URL) throws -> FinderAlias {
        let volumeValues = try volume.resourceValues(forKeys: [.volumeNameKey, .creationDateKey])
        let fileValues = try file.resourceValues(forKeys: [.creationDateKey])
        guard let volumeName = volumeValues.volumeName, let volumeCreated = volumeValues.creationDate,
              let fileCreated = fileValues.creationDate
        else { throw IconKitError("could not read the dates and names of \(file.path)") }
        let parent = file.deletingLastPathComponent()
        let relative = file.standardizedFileURL.path.dropFirst(volume.standardizedFileURL.path.count)
        guard relative.hasPrefix("/"), parent.standardizedFileURL.deletingLastPathComponent().path == volume.standardizedFileURL.path else {
            throw IconKitError("\(file.path) must be in a folder at the root of \(volume.path)")
        }
        return FinderAlias(
            volumeName: volumeName, volumeDate: hfsDate(volumeCreated),
            parentName: parent.lastPathComponent, parentID: try nodeID(parent),
            fileName: file.lastPathComponent, fileID: try nodeID(file), fileDate: hfsDate(fileCreated),
            posixPath: String(relative), mountPoint: "/Volumes/\(volumeName)")
    }

    /// On HFS+ the inode number is the catalog node ID.
    static func nodeID(_ url: URL) throws -> UInt32 {
        var info = stat()
        guard lstat(url.path, &info) == 0 else { throw IconKitError("cannot stat \(url.path)") }
        return UInt32(truncatingIfNeeded: info.st_ino)
    }

    // MARK: Encoding

    var data: Data {
        var body = Data()
        body.appendUInt16(0)                                  // kind: file
        body.append(Self.pascal(volumeName, field: 28))
        body.appendUInt32(volumeDate)
        body.append(contentsOf: Array("H+".utf8))             // file system: HFS+
        body.appendUInt16(5)                                  // disk type: ejectable
        body.appendUInt32(parentID)
        body.append(Self.pascal(fileName, field: 64))
        body.appendUInt32(fileID)
        body.appendUInt32(fileDate)
        body.append(Data(count: 8))                           // type and creator codes: none
        body.appendUInt16(0xFFFF)                             // levels from: unknown
        body.appendUInt16(0xFFFF)                             // levels to: unknown
        body.appendUInt32(0x0D02)                             // volume attributes, as DMG tools write them
        body.appendUInt16(0)                                  // volume file system ID
        body.append(Data(count: 10))

        func tag(_ number: Int16, _ value: Data) {
            body.appendUInt16(UInt16(bitPattern: number))
            body.appendUInt16(UInt16(value.count))
            body.append(value)
            if value.count % 2 == 1 { body.append(0) }
        }
        tag(0, Data(parentName.utf8))
        var parents = Data()
        parents.appendUInt32(parentID)
        tag(1, parents)
        tag(14, Self.unicode(fileName))
        tag(15, Self.unicode(volumeName))
        tag(18, Data(posixPath.utf8))
        tag(19, Data(mountPoint.utf8))
        tag(-1, Data())

        var record = Data(count: 4)                           // application: none
        record.appendUInt16(UInt16(4 + 2 + 2 + body.count))
        record.appendUInt16(2)                                // version
        record.append(body)
        return record
    }

    private static func pascal(_ string: String, field: Int) -> Data {
        let bytes = Array((string.data(using: .macOSRoman) ?? Data(string.utf8)).prefix(field - 1))
        var data = Data([UInt8(bytes.count)] + bytes)
        data.append(Data(count: field - data.count))
        return data
    }

    private static func unicode(_ string: String) -> Data {
        var data = Data()
        let units = Array(string.utf16)
        data.appendUInt16(UInt16(units.count))
        for unit in units { data.appendUInt16(unit) }
        return data
    }

    // MARK: Decoding

    init(volumeName: String, volumeDate: UInt32, parentName: String, parentID: UInt32, fileName: String,
         fileID: UInt32, fileDate: UInt32, posixPath: String, mountPoint: String) {
        self.volumeName = volumeName
        self.volumeDate = volumeDate
        self.parentName = parentName
        self.parentID = parentID
        self.fileName = fileName
        self.fileID = fileID
        self.fileDate = fileDate
        self.posixPath = posixPath
        self.mountPoint = mountPoint
    }

    /// Reads back the fields this tool cares about from any version 2 alias record.
    init(decoding data: Data) throws {
        let bytes = [UInt8](data)
        guard bytes.count >= 150 else { throw IconKitError("the alias is too short (\(bytes.count) bytes)") }
        func u16(_ offset: Int) -> UInt16 { UInt16(bytes[offset]) << 8 | UInt16(bytes[offset + 1]) }
        func u32(_ offset: Int) -> UInt32 { bytes[offset..<(offset + 4)].reduce(0) { $0 << 8 | UInt32($1) } }
        func pascal(_ offset: Int) -> String {
            String(data: Data(bytes[(offset + 1)..<(offset + 1 + Int(bytes[offset]))]), encoding: .macOSRoman) ?? ""
        }
        guard u16(4) == bytes.count, u16(6) == 2 else { throw IconKitError("not a version 2 alias of the right length") }
        // Offsets of the fixed part: kind 8, volume name 10 (28 bytes), volume date 38, file system
        // 42, disk type 44, parent 46, file name 50 (64 bytes), file 114, file date 118.
        volumeName = pascal(10)
        volumeDate = u32(38)
        parentID = u32(46)
        fileName = pascal(50)
        fileID = u32(114)
        fileDate = u32(118)
        parentName = ""
        posixPath = ""
        mountPoint = ""
        var p = 150
        while p + 4 <= bytes.count {
            let tag = Int16(bitPattern: u16(p)), length = Int(u16(p + 2))
            if tag == -1 { break }
            let value = Data(bytes[(p + 4)..<(p + 4 + length)])
            switch tag {
            case 0: parentName = String(decoding: value, as: UTF8.self)
            case 14: fileName = Self.decodeUnicode(value)
            case 15: volumeName = Self.decodeUnicode(value)
            case 18: posixPath = String(decoding: value, as: UTF8.self)
            case 19: mountPoint = String(decoding: value, as: UTF8.self)
            default: break
            }
            p += 4 + length + (length % 2)
        }
    }

    private static func decodeUnicode(_ data: Data) -> String {
        let bytes = [UInt8](data)
        guard bytes.count >= 2 else { return "" }
        let count = Int(UInt16(bytes[0]) << 8 | UInt16(bytes[1]))
        let units = (0..<min(count, (bytes.count - 2) / 2)).map { UInt16(bytes[2 + 2 * $0]) << 8 | UInt16(bytes[3 + 2 * $0]) }
        return String(decoding: units, as: UTF16.self)
    }
}

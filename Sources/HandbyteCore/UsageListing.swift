import Darwin

/// How a file shares its blocks with other files on APFS.
struct CloneState: Equatable {
    /// All blocks of the file are shared with at least one other file. These
    /// files have the same `id`.
    var full = false
    var id: UInt64 = 0
    /// Some blocks can be shared, and the file is not a full clone.
    var partial = false

    /// Reads the clone ID, the extended flags and the clone reference count,
    /// in this order, for the bits that are set in `returned`.
    init(returned: UInt32, reader: inout AttributeReader) {
        guard returned & UInt32(ATTR_CMNEXT_CLONEID) != 0, returned & UInt32(ATTR_CMNEXT_EXT_FLAGS) != 0 else { return }
        id = reader.next(UInt64.self)
        let flags = reader.next(UInt64.self)
        if returned & UInt32(ATTR_CMNEXT_CLONE_REFCNT) != 0 {
            full = reader.next(UInt32.self) > 1
        } else {
            // Without the reference count, use the flag. Each full clone has it.
            full = flags & UInt64(EF_SHARES_ALL_BLOCKS) != 0
        }
        partial = !full && flags & UInt64(EF_MAY_SHARE_BLOCKS) != 0
    }

    init() {}
}

/// Reads packed attributes of getattrlist(2) in order.
struct AttributeReader {
    private(set) var pointer: UnsafeRawPointer

    init(_ pointer: UnsafeRawPointer) {
        self.pointer = pointer
    }

    mutating func next<T>(_: T.Type) -> T {
        defer { pointer += MemoryLayout<T>.size }
        return pointer.loadUnaligned(as: T.self)
    }
}

/// One directory entry with the values of lstat that the storage scan uses.
struct UsageEntry {
    let name: String
    var isDirectory = false
    var isRegular = false
    var device: Int32 = 0
    var inode: UInt64 = 0
    var flags: UInt32 = 0
    var links: UInt32 = 0
    var allocatedBytes: Int64 = 0
    var logicalBytes: Int64 = 0
    var clone = CloneState()

    init(name: String) {
        self.name = name
    }

    init(name: String, status: stat) {
        self.name = name
        isDirectory = status.st_mode & S_IFMT == S_IFDIR
        isRegular = status.st_mode & S_IFMT == S_IFREG
        device = status.st_dev
        inode = status.st_ino
        flags = status.st_flags
        links = UInt32(status.st_nlink)
        allocatedBytes = Int64(status.st_blocks) * 512
        logicalBytes = Int64(status.st_size)
    }

    var identity: FileIdentity {
        FileIdentity(dev: UInt64(UInt32(bitPattern: device)), ino: inode)
    }

    private static var attributes: attrlist {
        var list = attrlist()
        list.bitmapcount = u_short(ATTR_BIT_MAP_COUNT)
        list.commonattr = UInt32(ATTR_CMN_RETURNED_ATTRS) | UInt32(ATTR_CMN_ERROR) | UInt32(ATTR_CMN_NAME)
            | UInt32(ATTR_CMN_DEVID) | UInt32(ATTR_CMN_OBJTYPE) | UInt32(ATTR_CMN_FLAGS) | UInt32(ATTR_CMN_FILEID)
        list.dirattr = UInt32(ATTR_DIR_MOUNTSTATUS)
        list.fileattr = UInt32(ATTR_FILE_LINKCOUNT) | UInt32(ATTR_FILE_ALLOCSIZE) | UInt32(ATTR_FILE_DATALENGTH)
        list.forkattr = UInt32(ATTR_CMNEXT_CLONEID) | UInt32(ATTR_CMNEXT_EXT_FLAGS) | UInt32(ATTR_CMNEXT_CLONE_REFCNT)
        return list
    }

    /// Lists a directory in byte order of the names. Returns the entries it
    /// could read and the first error. One getattrlistbulk call reads many
    /// entries.
    static func list(_ path: String) -> ([UsageEntry], String?) {
        let descriptor = open(path, O_RDONLY | O_DIRECTORY | O_CLOEXEC)
        guard descriptor >= 0 else { return ([], String(cString: strerror(errno))) }
        defer { close(descriptor) }
        var attributes = Self.attributes
        let size = 32 * 1024
        let buffer = UnsafeMutableRawPointer.allocate(byteCount: size, alignment: 8)
        defer { buffer.deallocate() }

        var entries: [UsageEntry] = []
        var failure: String?
        while true {
            let count = getattrlistbulk(descriptor, &attributes, buffer, size, UInt64(FSOPT_ATTR_CMN_EXTENDED))
            if count < 0, errno == EINTR { continue }
            if count < 0 {
                if failure == nil { failure = String(cString: strerror(errno)) }
                break
            }
            if count == 0 { break }
            var record = UnsafeRawPointer(buffer)
            for _ in 0..<count {
                let length = Int(record.loadUnaligned(as: UInt32.self))
                defer { record += length }
                let (entry, complete) = parse(record)
                if complete {
                    entries.append(entry)
                    continue
                }
                // A mount point or a firmlink gives the values of the
                // directory below it, and an entry can fail alone.
                var status = stat()
                if lstat(path == "/" ? "/" + entry.name : path + "/" + entry.name, &status) != 0 {
                    if errno != ENOENT, failure == nil { failure = String(cString: strerror(errno)) }
                    continue
                }
                entries.append(UsageEntry(name: entry.name, status: status))
            }
        }
        entries.sort { $0.name.utf8.lexicographicallyPrecedes($1.name.utf8) }
        return (entries, failure)
    }

    /// Reads one record of getattrlistbulk. `complete` is false when the
    /// record does not give the values that lstat gives.
    private static func parse(_ record: UnsafeRawPointer) -> (entry: UsageEntry, complete: Bool) {
        var reader = AttributeReader(record + 4)
        let returned = reader.next(attribute_set_t.self)
        var failed = false
        if returned.commonattr & UInt32(ATTR_CMN_ERROR) != 0 {
            failed = reader.next(UInt32.self) != 0
        }
        let start = reader.pointer
        let reference = reader.next(attrreference_t.self)
        var entry = UsageEntry(name: String(cString: (start + Int(reference.attr_dataoffset)).assumingMemoryBound(to: CChar.self)))
        let common = UInt32(ATTR_CMN_DEVID) | UInt32(ATTR_CMN_OBJTYPE) | UInt32(ATTR_CMN_FLAGS) | UInt32(ATTR_CMN_FILEID)
        guard !failed, returned.commonattr & common == common else { return (entry, false) }
        entry.device = reader.next(Int32.self)
        let type = reader.next(UInt32.self)
        entry.flags = reader.next(UInt32.self)
        entry.inode = reader.next(UInt64.self)
        entry.isDirectory = type == VDIR.rawValue
        entry.isRegular = type == VREG.rawValue
        if entry.flags & UInt32(SF_FIRMLINK) != 0 { return (entry, false) }
        if entry.isDirectory {
            guard returned.dirattr & UInt32(ATTR_DIR_MOUNTSTATUS) != 0 else { return (entry, false) }
            return (entry, reader.next(UInt32.self) & UInt32(DIR_MNTSTATUS_MNTPOINT) == 0)
        }
        let file = UInt32(ATTR_FILE_LINKCOUNT) | UInt32(ATTR_FILE_ALLOCSIZE) | UInt32(ATTR_FILE_DATALENGTH)
        guard returned.fileattr & file == file else { return (entry, false) }
        entry.links = reader.next(UInt32.self)
        entry.allocatedBytes = reader.next(Int64.self)
        entry.logicalBytes = reader.next(Int64.self)
        entry.clone = CloneState(returned: returned.forkattr, reader: &reader)
        return (entry, true)
    }
}

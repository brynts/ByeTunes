import Foundation

/// Generates the legacy iPod ArtworkDB binary file format
/// iOS 26 still requires this file at /iTunes_Control/Artwork/ArtworkDB
class ArtworkDBBuilder {
    
    /// Artwork entry representing a song with artwork
    struct ArtworkEntry {
        let imageID: UInt32          // Unique artwork ID (e.g., 100, 101, 102...)
        let songDBID: UInt64         // item_pid from MediaLibrary
        let artworkHash: String      // Hash path like "31/0b86e0..."
    }
    
    // MARK: - Public API
    
    /// Generates an ArtworkDB file containing entries for the provided artwork
    /// - Parameter entries: List of artwork entries to include
    /// - Returns: Binary data for the ArtworkDB file
    static func generateArtworkDB(entries: [ArtworkEntry]) -> Data {
        var data = Data()
        
        // We need to calculate total sizes before writing
        // Structure: mhfd -> mhsd(1) -> mhli -> [mhii entries] -> mhsd(2) -> mhla -> mhsd(3) -> mhlf -> [mhif entries]
        
        let mhfdSize: UInt32 = 0x84       // 132 bytes
        let mhsdSize: UInt32 = 0x60       // 96 bytes
        let mhliSize: UInt32 = 0x5C       // 92 bytes
        let mhlaSize: UInt32 = 0x5C       // 92 bytes
        let mhlfSize: UInt32 = 0x5C       // 92 bytes
        let mhiiSize: UInt32 = 0x98       // 152 bytes per image item
        let mhifSize: UInt32 = 0x7C       // 124 bytes per file reference
        
        let imageCount = UInt32(entries.count)
        
        // Calculate section sizes
        let section1TotalSize = mhsdSize + mhliSize + (mhiiSize * imageCount)
        let section2TotalSize = mhsdSize + mhlaSize
        let section3TotalSize = mhsdSize + mhlfSize + (mhifSize * imageCount)
        
        let totalFileSize = mhfdSize + section1TotalSize + section2TotalSize + section3TotalSize
        
        // ============ mhfd (File Header) ============
        data.append(contentsOf: "mhfd".utf8)                    // 0: magic
        data.append(uint32LE: mhfdSize)                         // 4: header length
        data.append(uint32LE: totalFileSize)                    // 8: total file length
        data.append(uint32LE: 0)                                // 12: unknown
        data.append(uint32LE: 0)                                // 16: unknown  
        data.append(uint32LE: 3)                                // 20: number of sections
        data.append(uint32LE: 0)                                // 24: unknown
        data.append(uint32LE: 100)                              // 28: next image ID
        data.append(Data(count: Int(mhfdSize - 32)))            // padding to 132 bytes
        
        // ============ mhsd Section 1 (Image List) ============
        data.append(contentsOf: "mhsd".utf8)                    // 0: magic
        data.append(uint32LE: mhsdSize)                         // 4: header length
        data.append(uint32LE: section1TotalSize)                // 8: total section length
        data.append(uint32LE: 1)                                // 12: section type (1 = image list)
        data.append(Data(count: Int(mhsdSize - 16)))            // padding
        
        // ============ mhli (Image List) ============
        data.append(contentsOf: "mhli".utf8)                    // 0: magic
        data.append(uint32LE: mhliSize)                         // 4: header length
        data.append(uint32LE: imageCount)                       // 8: number of images
        data.append(Data(count: Int(mhliSize - 12)))            // padding
        
        // ============ mhii entries (one per artwork) ============
        for entry in entries {
            data.append(contentsOf: "mhii".utf8)                // 0: magic
            data.append(uint32LE: mhiiSize)                     // 4: header length  
            data.append(uint32LE: mhiiSize)                     // 8: total length (no children for now)
            data.append(uint32LE: 0)                            // 12: number of children
            data.append(uint32LE: entry.imageID)                // 16: image ID
            data.append(uint64LE: entry.songDBID)               // 20: song DBID (item_pid)
            data.append(uint32LE: 0)                            // 28: unknown
            data.append(uint32LE: 0)                            // 32: source image size
            data.append(Data(count: Int(mhiiSize - 36)))        // padding to 152 bytes
        }
        
        // ============ mhsd Section 2 (Album List) ============
        data.append(contentsOf: "mhsd".utf8)
        data.append(uint32LE: mhsdSize)
        data.append(uint32LE: section2TotalSize)
        data.append(uint32LE: 2)                                // section type 2 = album list
        data.append(Data(count: Int(mhsdSize - 16)))
        
        // ============ mhla (Album List - empty) ============
        data.append(contentsOf: "mhla".utf8)
        data.append(uint32LE: mhlaSize)
        data.append(uint32LE: 0)                                // 0 albums
        data.append(Data(count: Int(mhlaSize - 12)))
        
        // ============ mhsd Section 3 (File List) ============
        data.append(contentsOf: "mhsd".utf8)
        data.append(uint32LE: mhsdSize)
        data.append(uint32LE: section3TotalSize)
        data.append(uint32LE: 3)                                // section type 3 = file list
        data.append(Data(count: Int(mhsdSize - 16)))
        
        // ============ mhlf (File List) ============
        data.append(contentsOf: "mhlf".utf8)
        data.append(uint32LE: mhlfSize)
        data.append(uint32LE: imageCount)                       // number of files
        data.append(Data(count: Int(mhlfSize - 12)))
        
        // ============ mhif entries (one per image format) ============
        // We need to define image formats - using common iPod sizes
        for (index, _) in entries.enumerated() {
            data.append(contentsOf: "mhif".utf8)                // 0: magic
            data.append(uint32LE: mhifSize)                     // 4: header length
            data.append(uint32LE: mhifSize)                     // 8: total length
            data.append(uint32LE: UInt32(index + 1))            // 12: correlationID
            data.append(uint32LE: 0)                            // 16: image size
            data.append(Data(count: Int(mhifSize - 20)))        // padding
        }
        
        return data
    }
    
    /// Generates an empty ArtworkDB (skeleton structure with no artwork)
    static func generateEmptyArtworkDB() -> Data {
        return generateArtworkDB(entries: [])
    }
}

// MARK: - Data Extension for Little-Endian Writing

extension Data {
    mutating func append(uint32LE value: UInt32) {
        var v = value.littleEndian
        Swift.withUnsafeBytes(of: &v) { self.append(contentsOf: $0) }
    }
    
    mutating func append(uint64LE value: UInt64) {
        var v = value.littleEndian
        Swift.withUnsafeBytes(of: &v) { self.append(contentsOf: $0) }
    }
}

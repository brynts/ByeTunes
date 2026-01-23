import Foundation
import AVFoundation

/// Representa la metadata
struct SongMetadata: Identifiable {
    let id = UUID()
    
    var localURL: URL
    var title: String
    var artist: String
    var album: String
    var albumArtist: String?
    var genre: String
    var year: Int
    var durationMs: Int
    var fileSize: Int
    var remoteFilename: String
    var artworkData: Data?
    
    var trackNumber: Int?
    var trackCount: Int?
    var discNumber: Int?
    var discCount: Int?
    
    /// Artwork token pa referencia en la database
    var artworkToken: String {
        return "local://\(remoteFilename)"
    }
    
    /// Generar un filename random de 4 chars tipo iTunes
    static func generateRemoteFilename(withExtension ext: String? = nil) -> String {
        let letters = "ABCDEFGHIJKLMNOPQRSTUVWXYZ"
        let randomName = String((0..<4).map { _ in letters.randomElement()! })
        let e = (ext?.isEmpty == false) ? ext!.lowercased() : "mp3"
        return "\(randomName).\(e)"
    }
    
    /// Generar un persistent ID random de 64-bit
    static func generatePersistentId() -> Int64 {
        return Int64.random(in: 1_000_000_000_000_000_000...Int64.max)
    }
    
    /// Generar bytes de grouping key sorting
    static func generateGroupingKey(_ text: String) -> Data {
        guard !text.isEmpty else { return Data() }
        
        var result = [UInt8]()
        for char in text.uppercased() {
            if char >= "A" && char <= "Z" {
                result.append(UInt8(char.asciiValue! - Character("A").asciiValue! + 1))
            } else if char == " " {
                result.append(0x04)
            } else if char == "/" {
                result.append(0x0A)
            }
        }
        return Data(result)
    }

    /// Extract metadata from an MP3 file using AVFoundation
    static func fromURL(_ url: URL) async throws -> SongMetadata {
        let asset = AVURLAsset(url: url)
        
        // Get duration
        let duration = try await asset.load(.duration)
        let durationMs = Int(CMTimeGetSeconds(duration) * 1000)
        
        // Get file size
        let fileSize = (try? FileManager.default.attributesOfItem(atPath: url.path)[.size] as? Int) ?? 0
        
        // Parse filename as fallback (e.g., "Artist - Title.flac" or "Title - Artist.flac")
        let filenameWithoutExt = url.deletingPathExtension().lastPathComponent
        var title = filenameWithoutExt
        var artist = "Unknown Artist"
        var album = "Unknown Album"
        var albumArtist: String?
        var genre = "Unknown Genre"
        var year = Calendar.current.component(.year, from: Date())
        var artworkData: Data?
        
        var trackNumber: Int?
        var trackCount: Int?
        var discNumber: Int?
        var discCount: Int?
        
        // Try to parse "Title - Artist" or "Artist - Title" from filename
        if filenameWithoutExt.contains(" - ") {
            let parts = filenameWithoutExt.components(separatedBy: " - ")
            if parts.count >= 2 {
                // Assume format: "Title - Artist"
                title = parts[0].trimmingCharacters(in: .whitespaces)
                artist = parts[1].trimmingCharacters(in: .whitespaces)
            }
        }
        
        // Try common metadata first (works for MP3, M4A)
        let commonMetadata = try await asset.load(.commonMetadata)
        
        for item in commonMetadata {
            guard let key = item.commonKey else { continue }
            
            switch key {
            case .commonKeyTitle:
                if let value = try? await item.load(.stringValue), !value.isEmpty {
                    title = value
                }
            case .commonKeyArtist:
                if let value = try? await item.load(.stringValue), !value.isEmpty {
                    artist = value
                }
            case .commonKeyAlbumName:
                if let value = try? await item.load(.stringValue), !value.isEmpty {
                    album = value
                }
            case .commonKeyType:
                if let value = try? await item.load(.stringValue), !value.isEmpty {
                    genre = value
                }
            case .commonKeyCreationDate:
                if let value = try? await item.load(.stringValue),
                   let yearInt = Int(value.prefix(4)) {
                    year = yearInt
                }
            case .commonKeyArtwork:
                if let data = try? await item.load(.dataValue) {
                    artworkData = data
                    print("[SongMetadata] Extracted artwork: \(data.count) bytes")
                }
            default: break
            }
        }
        
        // DEEP SCAN: Load ALL metadata formats to find Track/Disc numbers (ID3 'TRCK', iTunes 'trkn', Vorbis 'TRACKNUMBER')
        let allMetadata = try await asset.load(.metadata)
        // print("[SongMetadata] Scanning \(allMetadata.count) items for Track/Disc info...")
        
        for item in allMetadata {
            // Get key as String (could be "TRCK", "trkn", "TRACKNUMBER", etc.)
            var keyString = ""
            if let strKey = item.key as? String {
                keyString = strKey
            } else if let intKey = item.key as? Int {
                // ID3v2.3 tags sometimes come as Int codes? Rarely. Usually String identifiers.
                // But AVMetadataItem.identifier is more reliable.
                keyString = "\(intKey)"
            }
            
            let identifier = item.identifier?.rawValue ?? ""
            let combined = "\(identifier)|\(keyString)".uppercased()
            
            // print("[SongMetadata] Key: \(combined)") // Uncomment to debug
            
            // TRACK NUMBER
            if trackNumber == nil {
                if combined.contains("TRCK") || combined.contains("TRACK") || combined.contains("TRKN") || keyString.lowercased() == "trkn" {
                    // Try parsing as String "1/12"
                    if let stringVal = try? await item.load(.stringValue) {
                        let components = stringVal.components(separatedBy: "/")
                        if let t = Int(components[0]) { trackNumber = t }
                        if components.count > 1, let tc = Int(components[1]) { trackCount = tc }
                    }
                    // Try parsing as binary data (iTunes 'trkn' atom: 8 bytes)
                    else if let dataVal = try? await item.load(.dataValue), dataVal.count >= 8 {
                        // Bytes 2-3 = Track Num, 4-5 = Track Count (Big Endian)
                        let track = dataVal.withUnsafeBytes { $0.load(fromByteOffset: 2, as: UInt16.self).bigEndian }
                        let total = dataVal.withUnsafeBytes { $0.load(fromByteOffset: 4, as: UInt16.self).bigEndian }
                        if track > 0 { trackNumber = Int(track) }
                        if total > 0 { trackCount = Int(total) }
                    }
                }
            }
            
            // DISC NUMBER
            if discNumber == nil {
                if combined.contains("TPOS") || combined.contains("DISC") || combined.contains("DISK") || keyString.lowercased() == "disk" {
                     if let stringVal = try? await item.load(.stringValue) {
                        let components = stringVal.components(separatedBy: "/")
                        if let d = Int(components[0]) { discNumber = d }
                        if components.count > 1, let dc = Int(components[1]) { discCount = dc }
                     } else if let dataVal = try? await item.load(.dataValue), dataVal.count >= 6 { // 'disk' usually 6 bytes? or 8?
                         // Assuming similar structure to trkn
                         let disc = dataVal.withUnsafeBytes { $0.load(fromByteOffset: 2, as: UInt16.self).bigEndian }
                         let total = dataVal.withUnsafeBytes { $0.load(fromByteOffset: 4, as: UInt16.self).bigEndian }
                         if disc > 0 { discNumber = Int(disc) }
                         if total > 0 { discCount = Int(total) }
                     }
                }
            }

            // ARTWORK (Deep Scan / FLAC Fallback)
            if artworkData == nil {
                // Check keys that indicate artwork
                if combined.contains("ARTWORK") || combined.contains("PICTURE") || combined.contains("APIC") || combined.contains("COVR") {
                    if let data = try? await item.load(.dataValue), !data.isEmpty {
                        artworkData = data
                        print("[SongMetadata] Deep Scan extracted artwork: \(data.count) bytes (Key: \(combined))")
                    }
                }
            }

            // FLAC Vorbis Comments specific check (TITLE, ARTIST keys) if still unknown
            // This is moved here to ensure it runs after common metadata but before final fallback.
            // It also uses the `allMetadata` array.
            if let val = try? await item.load(.stringValue), !val.isEmpty {
                if (combined.contains("TITLE") || combined.contains("NAM")) && title == filenameWithoutExt { title = val }
                if (combined.contains("ARTIST") || combined.contains("PERFORMER")) && !combined.contains("ALBUMARTIST") && artist == "Unknown Artist" { artist = val }
                if combined.contains("ALBUM") && !combined.contains("ALBUMARTIST") && album == "Unknown Album" { album = val }
                if (combined.contains("GENRE") || combined.contains("GEN")) && genre == "Unknown Genre" { genre = val }
                
                // Album Artist
                if (combined.contains("ALBUMARTIST") || combined.contains("TPE2") || combined.contains("AART")) {
                   albumArtist = val
                }

                // Year extraction: check for DATE, YEAR, TYER (ID3v2.3), TDRC (ID3v2.4), ©day (iTunes/M4A)
                if year == Calendar.current.component(.year, from: Date()) {
                    if combined.contains("DATE") || combined.contains("YEAR") || combined.contains("TYER") || combined.contains("TDRC") || combined.contains("DAY") {
                        // Try to extract 4-digit year from the value (could be "2019", "2019-05-21", etc.)
                        if let yearInt = Int(val.prefix(4)), yearInt >= 1000 && yearInt <= 2100 {
                            year = yearInt
                            print("[SongMetadata] Extracted year: \(year) from key: \(combined)")
                        }
                    }
                }
            }
        }
        
        print("[SongMetadata] Final: title=\(title), artist=\(artist), album=\(album), track=\(trackNumber ?? 0)/\(trackCount ?? 0)")
        
        return SongMetadata(
            localURL: url,
            title: title,
            artist: artist,
            album: album,
            albumArtist: albumArtist,
            genre: genre,
            year: year,
            durationMs: durationMs,
            fileSize: fileSize,
            remoteFilename: generateRemoteFilename(withExtension: url.pathExtension),
            artworkData: artworkData,
            trackNumber: trackNumber,
            trackCount: trackCount,
            discNumber: discNumber,
            discCount: discCount
        )
    }
}

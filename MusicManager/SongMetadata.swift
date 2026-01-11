import Foundation
import AVFoundation

/// Representa la metadata
struct SongMetadata: Identifiable {
    let id = UUID()
    
    var localURL: URL
    var title: String
    var artist: String
    var album: String
    var genre: String
    var year: Int
    var durationMs: Int
    var fileSize: Int
    
    /// Filename remoto en el device
    var remoteFilename: String
    
    /// Artwork data sacada del MP3 (JPEG o PNG)
    var artworkData: Data?
    
    /// Artwork token pa referencia en la database
    var artworkToken: String {
        return "local://\(remoteFilename)"
    }
    
    /// Generar un filename random de 4 chars tipo iTunes
    /// Preserves given extension (e.g. "mp3", "flac"). Defaults to "mp3".
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
        let asset = AVAsset(url: url)
        
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
        var genre = "Unknown Genre"
        var year = Calendar.current.component(.year, from: Date())
        var artworkData: Data?
        
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
            default:
                break
            }
        }
        
        // For FLAC/Vorbis: Try loading ALL metadata if common metadata was incomplete
        // Also check if title looks like a UUID (sandbox file naming on iOS)
        let titleLooksLikeUUID = title.contains("-") && title.count > 36
        if artist == "Unknown Artist" || album == "Unknown Album" || titleLooksLikeUUID {
            let allMetadata = try await asset.load(.metadata)
            print("[SongMetadata] Checking \(allMetadata.count) format-specific metadata items for FLAC")
            
            for item in allMetadata {
                // Try multiple ways to get the key
                let identifierKey = item.identifier?.rawValue.uppercased() ?? ""
                let keyValue = (item.key as? String)?.uppercased() ?? ""
                let combinedKey = identifierKey + "|" + keyValue
                
                // Get the value for debugging
                let stringValue = try? await item.load(.stringValue)
                print("[SongMetadata] Key: \(combinedKey) = \(stringValue ?? "nil")")
                
                // Match by key or identifier containing the tag name
                if combinedKey.contains("TITLE") {
                    if let value = stringValue, !value.isEmpty {
                        title = value
                        print("[SongMetadata] ✓ Found title: \(value)")
                    }
                } else if combinedKey.contains("ARTIST") && !combinedKey.contains("ALBUMARTIST") {
                    if let value = stringValue, !value.isEmpty {
                        artist = value
                        print("[SongMetadata] ✓ Found artist: \(value)")
                    }
                } else if combinedKey.contains("ALBUM") && !combinedKey.contains("ALBUMARTIST") {
                    if let value = stringValue, !value.isEmpty {
                        album = value
                        print("[SongMetadata] ✓ Found album: \(value)")
                    }
                } else if combinedKey.contains("GENRE") {
                    if let value = stringValue, !value.isEmpty {
                        genre = value
                    }
                } else if combinedKey.contains("DATE") || combinedKey.contains("YEAR") {
                    if let value = stringValue, let yearInt = Int(value.prefix(4)) {
                        year = yearInt
                    }
                }
            }
        }
        
        print("[SongMetadata] Final: title=\(title), artist=\(artist), album=\(album)")
        
        return SongMetadata(
            localURL: url,
            title: title,
            artist: artist,
            album: album,
            genre: genre,
            year: year,
            durationMs: durationMs,
            fileSize: fileSize,
            remoteFilename: generateRemoteFilename(withExtension: url.pathExtension),
            artworkData: artworkData
        )
    }
}

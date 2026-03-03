import Foundation
import Darwin
import Combine
import UIKit
import CommonCrypto
import SQLite3


typealias IdevicePairingFile = OpaquePointer
typealias IdeviceProviderHandle = OpaquePointer
typealias HeartbeatClientHandle = OpaquePointer
typealias AfcClientHandle = OpaquePointer
typealias AfcFileHandle = OpaquePointer
typealias LockdowndClientHandle = OpaquePointer

typealias IdeviceErrorCode = UnsafeMutablePointer<IdeviceFfiError>?

let IdeviceSuccess: IdeviceErrorCode = nil


private let BUILD_VERSION = "v1.0.1"

class DeviceManager: ObservableObject {
    @Published var heartbeatReady: Bool = false
    @Published var connectionStatus: String = "Disconnected"
    var provider: IdeviceProviderHandle?
    var heartbeatThread: Thread?
    
    static var shared = DeviceManager()
    
    
    static let appGroupID = "group.com.edualexxis.MusicManager"
    
    var pairingFile: URL {
        let base: URL
        if let containerURL = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: Self.appGroupID) {
            base = containerURL
        } else {
            base = URL.documentsDirectory
        }
        return base.appendingPathComponent("pairing file").appendingPathComponent("pairingFile.plist")
    }
    
    
    static var sharedContainerURL: URL? {
        return FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: appGroupID)
    }
    
    private init() {
        print("===========================================")
        print("[DeviceManager] BUILD VERSION: \(BUILD_VERSION)")
        print("===========================================")
        print("[DeviceManager] Initializing...")
        let logPath = URL.documentsDirectory.appendingPathComponent("idevice-logs.txt").path
        let cString = strdup(logPath)
        defer { free(cString) }
        idevice_init_logger(Info, Disabled, cString)
        
        let folderPath = self.pairingFile.deletingLastPathComponent()
        do {
            if !FileManager.default.fileExists(atPath: folderPath.path) {
                try FileManager.default.createDirectory(at: folderPath, withIntermediateDirectories: true)
                Logger.shared.log("[DeviceManager] Created pairing file directory at: \(folderPath.path)")
            }
        } catch {
            Logger.shared.log("[DeviceManager] Error creating pairing directory: \(error)")
        }
    }
    
    
    
    func startHeartbeat(completion: ((Bool) -> Void)? = nil) {
        
        
        heartbeatThread = Thread {
            DispatchQueue.main.async {
                self.connectionStatus = "Connecting..."
            }
            
            self.establishHeartbeat { success in
                DispatchQueue.main.async {
                    if success {
                        
                        self.connectionStatus = "Connection Lost"
                        self.heartbeatReady = false
                    } else {
                        
                        self.connectionStatus = "Connection Failed"
                        self.heartbeatReady = false
                    }
                }
            }
        }
        heartbeatThread?.name = "HeartbeatThread"
        heartbeatThread?.start()
        
        if let completion = completion {
            DispatchQueue.global().async {
                
                for _ in 0..<20 {
                    if self.heartbeatReady {
                        DispatchQueue.main.async { completion(true) }
                        return
                    }
                    Thread.sleep(forTimeInterval: 0.5)
                }
                DispatchQueue.main.async { completion(false) }
            }
        }
    }

    func establishHeartbeat(_ completion: @escaping (Bool) -> Void) {
                 
        var addr = sockaddr_in()
        memset(&addr, 0, MemoryLayout<sockaddr_in>.size)
        addr.sin_family = sa_family_t(AF_INET)
        addr.sin_port = CFSwapInt16HostToBig(UInt16(LOCKDOWN_PORT))
        inet_pton(AF_INET, "10.7.0.1", &addr.sin_addr)
        
        var pairingPtr: IdevicePairingFile?
        let _ = idevice_pairing_file_read(pairingFile.path, &pairingPtr)
        
        if let oldProvider = provider {
            idevice_provider_free(oldProvider)
            provider = nil
        }
        
        let providerErr = withUnsafePointer(to: &addr) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { sockaddrPointer in
                idevice_tcp_provider_new(sockaddrPointer, pairingPtr, "Music-Provider", &provider)
            }
        }
        
        if provider == nil {
            Logger.shared.log("[DeviceManager] ERROR: Provider is nil. Err: \(String(describing: providerErr))")
            completion(false)
            return
        }
        
        var hbClient: HeartbeatClientHandle?
        let err = heartbeat_connect(provider, &hbClient)
        
        if err == IdeviceSuccess && hbClient != nil {
            Logger.shared.log("[DeviceManager] Heartbeat connected successfully!")
            
            DispatchQueue.main.async {
                self.connectionStatus = "Connected"
                self.heartbeatReady = true
            }
            
            
            while true {
                var newInterval: UInt64 = 0
                
                heartbeat_get_marco(hbClient, 10, &newInterval)
                
                heartbeat_send_polo(hbClient)
                
                DispatchQueue.main.async {
                    if !self.heartbeatReady {
                         self.heartbeatReady = true
                         self.connectionStatus = "Connected"
                    }
                }
                
                
                Thread.sleep(forTimeInterval: 5)
            }
            
            
            heartbeat_client_free(hbClient)
            completion(true) 
        } else {
            Logger.shared.log("[DeviceManager] ERROR: Heartbeat connection failed")
            completion(false)
        }
    }

    

    
    func sendSyncFinishedNotification() {
        var lockdownd: LockdowndClientHandle?
        let err = lockdownd_connect(provider, &lockdownd)
        
        if err == IdeviceSuccess {
            var port: UInt16 = 0
            var ssl: Bool = false
            _ = lockdownd_start_service(lockdownd, "com.apple.mobile.notification_proxy", &port, &ssl)
            lockdownd_client_free(lockdownd)
        }
    }
    
    
    
    
    func getDeviceProductVersion() -> String? {
        var lockdownd: LockdowndClientHandle?
        let err = lockdownd_connect(provider, &lockdownd)
        
        guard err == IdeviceSuccess, let client = lockdownd else {
            return nil
        }
        defer { lockdownd_client_free(client) }
        
        var plist: plist_t?
        // ProductVersion is the key for iOS version (e.g., "17.2.1")
        let valErr = lockdownd_get_value(client, "ProductVersion", nil, &plist)
        
        guard valErr == IdeviceSuccess, let versionPlist = plist else {
            return nil
        }
        defer { plist_free(versionPlist) }
        
        var cString: UnsafeMutablePointer<CChar>?
        plist_get_string_val(versionPlist, &cString)
        
        if let cString = cString {
            let version = String(cString: cString)
            plist_mem_free(cString)
            return version
        }
        
        return nil
    }
    
    func getDatabaseVersion() -> DatabaseVersion {
        guard let versionString = getDeviceProductVersion() else {
            Logger.shared.log("[DeviceManager] Could not detect version, defaulting to iOS 16/26 schema")
            return .ios(16)
        }
        
        Logger.shared.log("[DeviceManager] Detected device version: \(versionString)")
        let components = versionString.split(separator: ".").compactMap { Int($0) }
        guard let major = components.first else { return .ios(16) }
        
        // Check for subscription status (this is a heuristic, might need refinement)
        // For now, let's look for a specific folder or property if we can, 
        // but given the user's specific request for "ios 26 music subscription on", 
        // we'll assume it's a version 26 specific variant for now.
        // If the user wants to toggle this, we might need a UI setting.
        
        return .ios(major)
    }

    func triggerATCSync(completion: @escaping (Bool) -> Void) {
        DispatchQueue.global(qos: .userInitiated).async {
            var lockdownd: LockdowndClientHandle?
            let err = lockdownd_connect(self.provider, &lockdownd)
            
            guard err == IdeviceSuccess else {
                print("[DeviceManager] Failed to connect lockdownd for ATC")
                completion(false)
                return
            }
            
            var port: UInt16 = 0
            var ssl: Bool = false
            let _ = lockdownd_start_service(lockdownd, "com.apple.atc", &port, &ssl)
            
            lockdownd_client_free(lockdownd)
            
            if port > 0 {
                
                completion(true)
            } else {
                print("[DeviceManager] Failed to get ATC port")
                completion(false)
            }
        }
    }
    
    
    

    func addSongToDevice(localURL: URL, filename: String, completion: @escaping (Bool) -> Void) {
        Logger.shared.log("[DeviceManager] addSongToDevice called for: \(filename)")
        
        DispatchQueue.global(qos: .userInitiated).async {
            var afc: AfcClientHandle?
            var file: AfcFileHandle?
            
            let needsSecurityScope = localURL.startAccessingSecurityScopedResource()
            Logger.shared.log("[DeviceManager] Security scoped access needed: \(needsSecurityScope)")
            defer {
                if needsSecurityScope {
                    localURL.stopAccessingSecurityScopedResource()
                }
            }
            
            Logger.shared.log("[DeviceManager] File exists: \(FileManager.default.fileExists(atPath: localURL.path))")

            Logger.shared.log("[DeviceManager] Connecting AFC client...")
            afc_client_connect(self.provider, &afc)
            Logger.shared.log("[DeviceManager] AFC client connected: \(afc != nil)")
            
            guard afc != nil else {
                Logger.shared.log("[DeviceManager] ERROR: AFC client is nil")
                completion(false)
                return
            }
            
            
            let musicDir = "/iTunes_Control/Music/F00"
            Logger.shared.log("[DeviceManager] Creating directory: \(musicDir)")
            afc_make_directory(afc, musicDir)
            
            let remotePath = "\(musicDir)/\(filename)"
            Logger.shared.log("[DeviceManager] Opening remote file: \(remotePath)")
            afc_file_open(afc, remotePath, AfcWrOnly, &file)
            
            guard file != nil else {
                Logger.shared.log("[DeviceManager] ERROR: Could not open remote file")
                afc_client_free(afc)
                completion(false)
                return
            }
            
            if let data = try? Data(contentsOf: localURL) {
                
                data.withUnsafeBytes { buffer in
                    if let base = buffer.baseAddress?.assumingMemoryBound(to: UInt8.self) {
                        afc_file_write(file, base, data.count)
                    }
                }
                
            } else {
                Logger.shared.log("[DeviceManager] ERROR: Could not read file data from \(localURL.path)")
                afc_file_close(file)
                afc_client_free(afc)
                completion(false)
                return
            }
            
            afc_file_close(file)
            afc_client_free(afc)
            
            self.sendSyncFinishedNotification()
            Logger.shared.log("[DeviceManager] addSongToDevice complete")
            completion(true)
        }
    }
    
    
    
    func removeFileFromDevice(remotePath: String, completion: @escaping (Bool) -> Void) {
        Logger.shared.log("[DeviceManager] removeFileFromDevice called for: \(remotePath)")
        
        DispatchQueue.global(qos: .userInitiated).async {
            var afc: AfcClientHandle?
            
            afc_client_connect(self.provider, &afc)
            
            guard afc != nil else {
                Logger.shared.log("[DeviceManager] ERROR: AFC client is nil for deletion")
                completion(false)
                return
            }
            
            
            let err = afc_remove_path(afc, remotePath)
            
            
            afc_client_free(afc)
            completion(err == nil)
        }
    }
    
    
    
    func deleteMediaLibrary(completion: @escaping (Bool) -> Void) {
        Logger.shared.log("[DeviceManager] DELETING MEDIA LIBRARY (NUKE)...")
        
        DispatchQueue.global(qos: .userInitiated).async {
            var afc: AfcClientHandle?
            let connectErr = afc_client_connect(self.provider, &afc)
            
            guard afc != nil else {
                Logger.shared.log("[DeviceManager] ERROR: AFC client is nil for library reset (Error: \(String(describing: connectErr)))")
                completion(false)
                return
            }
            
            
            
            let iTunesPath = "/iTunes_Control/iTunes"
            Logger.shared.log("[DeviceManager] Removing \(iTunesPath) and all contents...")
            
            

            _ = afc_remove_path_and_contents(afc, iTunesPath)
            
            
            Logger.shared.log("[DeviceManager] Recreating \(iTunesPath)...")
            _ = afc_make_directory(afc, iTunesPath)
            
            
             _ = afc_make_directory(afc, "/iTunes_Control/iTunes/Artwork")
             _ = afc_make_directory(afc, "/iTunes_Control/iTunes/Artwork/Originals")
            
            afc_client_free(afc)

            
            self.sendSyncFinishedNotification()
            Logger.shared.log("[DeviceManager] Library nuke complete.")
            completion(true)
        }
    }
    
    private func cleanUpOrphanedFiles(validFilenames: Set<String>, completion: @escaping (Int) -> Void) {
        DispatchQueue.global(qos: .userInitiated).async {
            var afc: AfcClientHandle?
            afc_client_connect(self.provider, &afc)
            
            guard afc != nil else {
                Logger.shared.log("[DeviceManager] GC: Failed to connect AFC")
                completion(0)
                return
            }
            
            let musicDir = "/iTunes_Control/Music/F00"
            var entries: UnsafeMutablePointer<UnsafeMutablePointer<CChar>?>?
            var count: Int = 0
            
            let err = afc_list_directory(afc, musicDir, &entries, &count)
            
            var deletedCount = 0
            
            if err == nil, let list = entries {
                for i in 0..<count {
                    if let ptr = list[i] {
                        let filename = String(cString: ptr)
                        if filename != "." && filename != ".." {
                            // If file on disk is NOT in the database (validFilenames), delete it.
                            if !validFilenames.contains(filename) {
                                let path = "\(musicDir)/\(filename)"
                                Logger.shared.log("[DeviceManager] GC: Deleting orphan -> \(filename)")
                                afc_remove_path(afc, path)
                                deletedCount += 1
                            }
                        }
                    }
                }
                free(entries)
            }
            
            afc_client_free(afc)
            completion(deletedCount)
        }
    }
    
    func downloadFileFromDevice(remotePath: String, localURL: URL, completion: @escaping (Bool) -> Void) {
        self.downloadFileFromDevice(remotePath: remotePath) { data in
            guard let data = data else {
                completion(false)
                return
            }
            do {
                try data.write(to: localURL)
                completion(true)
            } catch {
                Logger.shared.log("[DeviceManager] Error writing downloaded file: \(error)")
                completion(false)
            }
        }
    }
    
    
    func downloadFileFromDevice(remotePath: String, completion: @escaping (Data?) -> Void) {
        Logger.shared.log("[DeviceManager] downloadFileFromDevice called for: \(remotePath)")
        
        DispatchQueue.global(qos: .userInitiated).async {
            var afc: AfcClientHandle?
            var file: AfcFileHandle?
            
            afc_client_connect(self.provider, &afc)
            
            guard afc != nil else {
                Logger.shared.log("[DeviceManager] ERROR: AFC client is nil for download")
                completion(nil)
                return
            }
            
            afc_file_open(afc, remotePath, AfcRdOnly, &file)
            
            guard file != nil else {
                Logger.shared.log("[DeviceManager] File does not exist or cannot be opened: \(remotePath)")
                afc_client_free(afc)
                completion(nil)
                return
            }
            
            var fullData = Data()
            let chunkSize: UInt = 64 * 1024
            
            while true {
                var dataPtr: UnsafeMutablePointer<UInt8>? = nil
                var bytesRead: UInt = 0
                
                let err = afc_file_read(file, &dataPtr, chunkSize, &bytesRead)
                
                if err != nil || bytesRead == 0 {
                    break
                }
                
                if let dataPtr = dataPtr {
                    fullData.append(dataPtr, count: Int(bytesRead))
                    afc_file_read_data_free(dataPtr, Int(bytesRead))
                } else {
                    break
                }
            }
            
            afc_file_close(file)
            afc_client_free(afc)
            
            if fullData.count > 0 {
                Logger.shared.log("[DeviceManager] Downloaded \(fullData.count) bytes from \(remotePath)")
                completion(fullData)
            } else {
                Logger.shared.log("[DeviceManager] Failed to read file: \(remotePath)")
                completion(nil)
            }
        }
    }
    
    
    
    func uploadFileToDevice(localURL: URL, remotePath: String, completion: @escaping (Bool) -> Void) {
        Logger.shared.log("[DeviceManager] uploadFileToDevice called: \(localURL.lastPathComponent) -> \(remotePath)")
        
        DispatchQueue.global(qos: .userInitiated).async {
            var afc: AfcClientHandle?
            var file: AfcFileHandle?
            
            let needsSecurityScope = localURL.startAccessingSecurityScopedResource()
            defer {
                if needsSecurityScope {
                    localURL.stopAccessingSecurityScopedResource()
                }
            }
            
            afc_client_connect(self.provider, &afc)
            
            guard afc != nil else {
                Logger.shared.log("[DeviceManager] ERROR: AFC client is nil for upload")
                completion(false)
                return
            }
            
            
            let parentDir = (remotePath as NSString).deletingLastPathComponent
            afc_make_directory(afc, parentDir)

            // Force delete existing file to prevent appending/stitching
            afc_remove_path(afc, remotePath)
            
            afc_file_open(afc, remotePath, AfcWrOnly, &file)
            
            guard file != nil else {
                Logger.shared.log("[DeviceManager] ERROR: Could not open remote file: \(remotePath)")
                afc_client_free(afc)
                completion(false)
                return
            }
            
            
            if let data = try? Data(contentsOf: localURL) {
                
                data.withUnsafeBytes { buffer in
                    if let base = buffer.baseAddress?.assumingMemoryBound(to: UInt8.self) {
                        afc_file_write(file, base, data.count)
                    }
                }
                
                
                afc_file_close(file)
                
                
                var checkFile: AfcFileHandle?
                let ret = afc_file_open(afc, remotePath, AfcRdOnly, &checkFile)
                if ret == nil { 
                    if checkFile != nil {
                        afc_file_close(checkFile)
                    }
                    afc_client_free(afc)
                    completion(true)
                } else {
                    Logger.shared.log("[DeviceManager] ERROR: Verification failed for \(remotePath)")
                    afc_client_free(afc)
                    completion(false)
                }
            } else {
                Logger.shared.log("[DeviceManager] ERROR: Could not read file data")
                afc_file_close(file)
                afc_client_free(afc)
                completion(false)
                return
            }
        }
    }
    
    
    
    func listFiles(remotePath: String, completion: @escaping ([String]?) -> Void) {
        Logger.shared.log("[DeviceManager] listFiles called for: \(remotePath)")
        
        DispatchQueue.global(qos: .userInitiated).async {
            var afc: AfcClientHandle?
            afc_client_connect(self.provider, &afc)
            
            guard afc != nil else {
                Logger.shared.log("[DeviceManager] ERROR: AFC client is nil for listFiles")
                completion(nil)
                return
            }
            
            var entries: UnsafeMutablePointer<UnsafeMutablePointer<CChar>?>?
            var count: Int = 0
            
            let err = afc_list_directory(afc, remotePath, &entries, &count)
            
            var files: [String] = []
            
            if err == nil, let list = entries {
                for i in 0..<count {
                    if let ptr = list[i] {
                        let name = String(cString: ptr)
                        if name != "." && name != ".." {
                            files.append(name)
                        }
                    }
                }
                
                free(entries) 
            } else {
                Logger.shared.log("[DeviceManager] Error reading directory or empty: \(remotePath)")
            }
            
            afc_client_free(afc)
            completion(files)
        }
    }
    
    
    
    func injectSongs(songs: [SongMetadata], progress: @escaping (String) -> Void, completion: @escaping (Bool) -> Void) {
        Logger.shared.log("[DeviceManager] injectSongs called with \(songs.count) songs")

        var validSongs: [SongMetadata] = []
        
        let isBatch = songs.count > 1
        
        for var song in songs {
            
            if song.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                let filename = song.localURL.lastPathComponent
                Logger.shared.log("[DeviceManager] Sanitize: Empty title for '\(filename)', using filename.")
                song.title = filename
            }
            
            
            if song.artist.isEmpty { song.artist = "Unknown Artist" }
            if song.album.isEmpty { song.album = "Unknown Album" }
            
            
            if isBatch {
                if song.title == "Broken Heart" {
                    Logger.shared.log("[DeviceManager] Batch Mode: Skipping 'Broken Heart'")
                    continue
                }
                if song.artist == "Unknown Artist" && song.album == "Unknown Album" {
                    Logger.shared.log("[DeviceManager] Batch Mode: Skipping Unknown song '\(song.title)'")
                    continue
                }
            }
            
            validSongs.append(song)
        }
        
        Logger.shared.log("[DeviceManager] Processing \(validSongs.count) songs (Sanitized).")
        
        if validSongs.isEmpty {
            Logger.shared.log("[DeviceManager] ⚠️ ABORTING: No songs found.")
            DispatchQueue.main.async { completion(true) }
            return
        }
        

        DispatchQueue.global(qos: .userInitiated).async {
            
            Logger.shared.log("[DeviceManager] Step 0: Listing existing files in /iTunes_Control/Music/F00")
            var onDeviceFiles: Set<String> = []
            let semFiles = DispatchSemaphore(value: 0)
            
            self.listFiles(remotePath: "/iTunes_Control/Music/F00") { files in
                if let f = files {
                    onDeviceFiles = Set(f)
                }
                semFiles.signal()
            }
            semFiles.wait()
            Logger.shared.log("[DeviceManager] Found \(onDeviceFiles.count) actual files on device")
            
            
            progress("Checking for existing library...")
            Logger.shared.log("[DeviceManager] Step 1: Downloading existing database")
            
            let semaphoreDownload = DispatchSemaphore(value: 0)
            var existingDbData: Data?
            var walData: Data?
            var shmData: Data?
            
            self.downloadFileFromDevice(remotePath: "/iTunes_Control/iTunes/MediaLibrary.sqlitedb") { data in
                existingDbData = data
                semaphoreDownload.signal()
            }
            semaphoreDownload.wait()
            
            
            let semWal = DispatchSemaphore(value: 0)
            self.downloadFileFromDevice(remotePath: "/iTunes_Control/iTunes/MediaLibrary.sqlitedb-wal") { data in
                walData = data
                semWal.signal()
            }
            semWal.wait()
            
            
            let semShm = DispatchSemaphore(value: 0)
            self.downloadFileFromDevice(remotePath: "/iTunes_Control/iTunes/MediaLibrary.sqlitedb-shm") { data in
                shmData = data
                semShm.signal()
            }
            semShm.wait()
            
            
            progress("Setting up directories...")
            Logger.shared.log("[DeviceManager] Step 2: Setting up directories")
            var afc: AfcClientHandle?
            afc_client_connect(self.provider, &afc)
            
            guard afc != nil else {
                Logger.shared.log("[DeviceManager] ERROR: AFC client is nil")
                DispatchQueue.main.async { completion(false) }
                return
            }
            
            
            
            
            afc_make_directory(afc, "/iTunes_Control")
            afc_make_directory(afc, "/iTunes_Control/Music")
            afc_make_directory(afc, "/iTunes_Control/Music/F00")
            afc_make_directory(afc, "/iTunes_Control/iTunes")
            afc_make_directory(afc, "/iTunes_Control/iTunes/Artwork")
            afc_make_directory(afc, "/iTunes_Control/iTunes/Artwork/Originals")
            afc_make_directory(afc, "/iTunes_Control/iTunes/Artwork/Caches")
            afc_make_directory(afc, "/iTunes_Control/Artwork")
            Logger.shared.log("[DeviceManager] Step 2: Directories created")
            
            afc_client_free(afc)
            
            
            var dbURL: URL
            var existingFiles = Set<String>()
            var artworkInfo: [MediaLibraryBuilder.ArtworkInfo] = []
            
            do {
                
                if let existingData = existingDbData, existingData.count > 10000 {
                    progress("Merging with existing library...")
                    Logger.shared.log("[DeviceManager] Step 3: Merging with existing database (\(existingData.count) bytes)")
                    
                    let version = self.getDatabaseVersion()
                    let result = try MediaLibraryBuilder.addSongsToExistingDatabase(
                        existingDbData: existingData,
                        walData: walData,
                        shmData: shmData,
                        newSongs: validSongs,
                        existingOnDeviceFiles: onDeviceFiles,
                        version: version
                    )
                    dbURL = result.dbURL
                    existingFiles = result.existingFiles
                    artworkInfo = result.artworkInfo
                    
                    Logger.shared.log("[DeviceManager] Existing files on device: \(existingFiles.count), artwork entries: \(artworkInfo.count)")
                } else {
                    if existingDbData != nil {
                        Logger.shared.log("[DeviceManager] Existing database too small (\(existingDbData!.count) bytes), creating fresh")
                    }
                    
                    progress("Creating new library...")
                    Logger.shared.log("[DeviceManager] Step 3: Creating fresh database")
                    let version = self.getDatabaseVersion()
                    let createResult = try MediaLibraryBuilder.createDatabase(songs: validSongs, version: version)
                    dbURL = createResult.dbURL
                    artworkInfo = createResult.artworkInfo
                }
            } catch {
                
                
                Logger.shared.log("[DeviceManager] ⚠️ MERGE FAILED: \(error)")
                Logger.shared.log("[DeviceManager] Aborting to preserve existing library. User should restart their iPhone and try again.")
                progress("Error: Could not merge. Restart iPhone and retry.")
                DispatchQueue.main.async { completion(false) }
                return
            }
            
            
            progress("Uploading songs...")
            Logger.shared.log("[DeviceManager] Step 4: Uploading MP3 files")
            
            var uploadedCount = 0
            var skippedCount = 0
            
            
            for (index, song) in validSongs.enumerated() {
                
                if existingFiles.contains(song.remoteFilename) {
                    Logger.shared.log("[DeviceManager] Skipping (already exists): \(song.title)")
                    skippedCount += 1
                    continue
                }
                
                progress("Uploading \(index + 1)/\(validSongs.count): \(song.title)")
                
                
                let semaphore = DispatchSemaphore(value: 0)
                var uploadSuccess = false
                
                let remotePath = "/iTunes_Control/Music/F00/\(song.remoteFilename)"
                self.uploadFileToDevice(localURL: song.localURL, remotePath: remotePath) { success in
                    uploadSuccess = success
                    semaphore.signal()
                }
                
                semaphore.wait()
                
                if !uploadSuccess {
                    Logger.shared.log("[DeviceManager] ERROR: Failed to upload \(song.title)")
                    DispatchQueue.main.async { completion(false) }
                    return
                }
                
                uploadedCount += 1
                
                
                
                if let artworkData = song.artworkData, index < artworkInfo.count {
                    let info = artworkInfo[index]
                    let artworkRelativePath = info.artworkHash  
                    
                    let pathComponents = artworkRelativePath.components(separatedBy: "/")
                    let folderName = pathComponents.count >= 1 ? pathComponents[0] : "00"
                    let fileName = pathComponents.count >= 2 ? pathComponents[1] : "unknown"
                    
                    let artworkDir = "/iTunes_Control/iTunes/Artwork/Originals/\(folderName)"
                    let artworkPath = "/iTunes_Control/iTunes/Artwork/Originals/\(artworkRelativePath)"
                    
                    Logger.shared.log("[DeviceManager] Uploading artwork for: \(song.title) -> \(artworkPath)")
                    
                    
                    var afcArt: AfcClientHandle?
                    afc_client_connect(self.provider, &afcArt)
                    if afcArt != nil {
                        afc_make_directory(afcArt, "/iTunes_Control/iTunes/Artwork")
                        afc_make_directory(afcArt, "/iTunes_Control/iTunes/Artwork/Originals")
                        afc_make_directory(afcArt, artworkDir)
                        afc_client_free(afcArt)
                    }
                    
                    
                    let tempArtwork = FileManager.default.temporaryDirectory.appendingPathComponent(fileName)
                    try? artworkData.write(to: tempArtwork)
                    
                    
                    let artworkSem = DispatchSemaphore(value: 0)
                    self.uploadFileToDevice(localURL: tempArtwork, remotePath: artworkPath) { _ in
                        artworkSem.signal()
                    }
                    artworkSem.wait()
                    
                    try? FileManager.default.removeItem(at: tempArtwork)
                    print("[DeviceManager] Artwork uploaded to: \(artworkPath)")
                }
            }
            
            print("[DeviceManager] Uploaded: \(uploadedCount), Skipped: \(skippedCount)")
            
            
            
            Logger.shared.log("[DeviceManager] Step 4.5: ArtworkDB generation SKIPPED - iOS handles artwork internally")

            
            
            progress("Uploading database...")
            Logger.shared.log("[DeviceManager] Step 5: Uploading database (Atomic Upgrade)")
            
            let tempDBPath = "/iTunes_Control/iTunes/MediaLibrary.sqlitedb.temp"
            let finalDBPath = "/iTunes_Control/iTunes/MediaLibrary.sqlitedb"
            let shmPath = "/iTunes_Control/iTunes/MediaLibrary.sqlitedb-shm"
            let walPath = "/iTunes_Control/iTunes/MediaLibrary.sqlitedb-wal"
            
            
            let semUploadDB = DispatchSemaphore(value: 0)
            var dbUploadSuccess = false
            self.uploadFileToDevice(localURL: dbURL, remotePath: tempDBPath) { success in
                dbUploadSuccess = success
                semUploadDB.signal()
            }
            semUploadDB.wait()
            
            if !dbUploadSuccess {
                Logger.shared.log("[DeviceManager] ERROR: Failed to upload temp database")
                DispatchQueue.main.async { completion(false) }
                return
            }
            
            
            var afcSwap: AfcClientHandle?
            afc_client_connect(self.provider, &afcSwap)
            
            guard afcSwap != nil else {
                Logger.shared.log("[DeviceManager] ERROR: Failed to connect AFC for atomic swap")
                DispatchQueue.main.async { completion(false) }
                return
            }
            
            
            afc_remove_path(afcSwap, shmPath)
            afc_remove_path(afcSwap, walPath)
            
            
            afc_remove_path(afcSwap, finalDBPath)
            
            
            let renameErr = afc_rename_path(afcSwap, tempDBPath, finalDBPath)
            
            if renameErr != nil {
                Logger.shared.log("[DeviceManager] ERROR: Failed to rename database (Error: \(renameErr!))")
                 
                 afc_remove_path(afcSwap, tempDBPath)
                 afc_client_free(afcSwap)
                 DispatchQueue.main.async { completion(false) }
                 return
            }
            
            Logger.shared.log("[DeviceManager] Database swapped successfully.")
            afc_client_free(afcSwap)
            
            
            
            progress("Finalizing...")
            Logger.shared.log("[DeviceManager] Step 6: Garbage Collection")
            
            // CRITICAL FIX: Ensure BOTH existing files AND newly added files are protected from GC
            let newFilenames = validSongs.map { $0.remoteFilename }
            let allValidFiles = existingFiles.union(newFilenames)
            
            Logger.shared.log("[DeviceManager] GC Whitelist: \(allValidFiles.count) files (Old: \(existingFiles.count), New: \(newFilenames.count))")

            self.cleanUpOrphanedFiles(validFilenames: allValidFiles) { deletedCount in
                if deletedCount > 0 {
                   Logger.shared.log("[DeviceManager] Garbage Collection finished. Deleted \(deletedCount) orphaned files.")
                } else {
                   Logger.shared.log("[DeviceManager] Garbage Collection finished. No orphans found.")
                }
                
                Logger.shared.log("[DeviceManager] Step 7: Sending sync notification")
                self.sendSyncFinishedNotification()
                
                progress("Complete! Restart your iPhone.")
                Logger.shared.log("[DeviceManager] Injection complete!")
                DispatchQueue.main.async { completion(true) }
            }
        }
    }
    
    
    
    
    
    func injectSongsAsPlaylist(songs: [SongMetadata], playlistName: String? = nil, targetPlaylistPid: Int64? = nil, progress: @escaping (String) -> Void, completion: @escaping (Bool) -> Void) {
        Logger.shared.log("[DeviceManager] injectSongsAsPlaylist called with \(songs.count) songs, playlist: '\(playlistName ?? "Existing")'")
        
            var validSongs: [SongMetadata] = []
        for var song in songs {
            if song.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                let filename = song.localURL.lastPathComponent
                song.title = filename
            }
            if song.artist.isEmpty { song.artist = "Unknown Artist" }
            if song.album.isEmpty { song.album = "Unknown Album" }
            validSongs.append(song)
        }
        
        if validSongs.isEmpty {
            Logger.shared.log("[DeviceManager] ⚠️ ABORTING: No songs for playlist.")
            DispatchQueue.main.async { completion(true) }
            return
        }
        

        
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self = self else { return }
            
            
            Logger.shared.log("[DeviceManager] Step 0: Listing existing files in /iTunes_Control/Music/F00")
            var onDeviceFiles: Set<String> = []
            let semFiles = DispatchSemaphore(value: 0)
            
            self.listFiles(remotePath: "/iTunes_Control/Music/F00") { files in
                if let f = files {
                    onDeviceFiles = Set(f)
                }
                semFiles.signal()
            }
            semFiles.wait()
            Logger.shared.log("[DeviceManager] Found \(onDeviceFiles.count) actual files on device")

            
            progress("Checking for existing library...")
            Logger.shared.log("[DeviceManager] Step 1: Downloading existing database")
            
            let semaphoreDownload = DispatchSemaphore(value: 0)
            var existingDbData: Data?
            var walData: Data?
            var shmData: Data?
            
            self.downloadFileFromDevice(remotePath: "/iTunes_Control/iTunes/MediaLibrary.sqlitedb") { data in
                existingDbData = data
                semaphoreDownload.signal()
            }
            semaphoreDownload.wait()
            
            
            let semWal = DispatchSemaphore(value: 0)
            self.downloadFileFromDevice(remotePath: "/iTunes_Control/iTunes/MediaLibrary.sqlitedb-wal") { data in
                walData = data
                semWal.signal()
            }
            semWal.wait()
            
            let semShm = DispatchSemaphore(value: 0)
            self.downloadFileFromDevice(remotePath: "/iTunes_Control/iTunes/MediaLibrary.sqlitedb-shm") { data in
                shmData = data
                semShm.signal()
            }
            semShm.wait()
            
            
            var afc: AfcClientHandle?
            afc_client_connect(self.provider, &afc)
            if afc != nil {
                
                
                
                afc_make_directory(afc, "/iTunes_Control/Music/F00")
                afc_make_directory(afc, "/iTunes_Control/iTunes/Artwork/Originals")
                afc_client_free(afc)
            }
            
            
            var dbURL: URL
            var existingFiles = Set<String>()
            var artworkInfo: [MediaLibraryBuilder.ArtworkInfo] = []

            
            do {
                if let existingData = existingDbData, existingData.count > 10000 {
                    progress("Merging with existing library...")
                    Logger.shared.log("[DeviceManager] Step 3: Merging with existing database (\(existingData.count) bytes)")
                    
                    let version = self.getDatabaseVersion()
                    let result = try MediaLibraryBuilder.addSongsToExistingDatabase(
                        existingDbData: existingData,
                        walData: walData,
                        shmData: shmData,
                        newSongs: validSongs, 
                        playlistName: playlistName,
                        targetPlaylistPid: targetPlaylistPid,
                        existingOnDeviceFiles: onDeviceFiles,
                        version: version
                    )
                    dbURL = result.dbURL
                    existingFiles = result.existingFiles
                    artworkInfo = result.artworkInfo

                } else {
                    progress("Creating new library with playlist...")
                    Logger.shared.log("[DeviceManager] Step 3: Creating fresh database with playlist")
                    let version = self.getDatabaseVersion()
                    let createResult = try MediaLibraryBuilder.createDatabase(songs: validSongs, version: version, playlistName: playlistName)
                    dbURL = createResult.dbURL
                    artworkInfo = createResult.artworkInfo

                }
            } catch {
                Logger.shared.log("[DeviceManager] ⚠️ PLAYLIST MERGE FAILED: \(error)")
                Logger.shared.log("[DeviceManager] Aborting to preserve existing library. User should restart their iPhone and try again.")
                progress("Error: Could not merge. Restart iPhone and retry.")
                DispatchQueue.main.async { completion(false) }
                return
            }
            
            
            progress("Uploading songs...")
            
            var uploadedCount = 0
            
            for (index, song) in validSongs.enumerated() {
                
                if existingFiles.contains(song.remoteFilename) {
                    continue
                }
                
                progress("Uploading \(index + 1)/\(validSongs.count): \(song.title)")
                
                let semaphore = DispatchSemaphore(value: 0)
                var uploadSuccess = false
                let remotePath = "/iTunes_Control/Music/F00/\(song.remoteFilename)"
                
                self.uploadFileToDevice(localURL: song.localURL, remotePath: remotePath) { success in
                    uploadSuccess = success
                    semaphore.signal()
                }
                semaphore.wait()
                
                if !uploadSuccess {
                    Logger.shared.log("[DeviceManager] ERROR: Failed to upload \(song.title)")
                    DispatchQueue.main.async { completion(false) }
                    return
                }
                uploadedCount += 1
                
                

            }
            
            

            
            
            
            var artworkIndex = 0
            
            for song in validSongs {
                 if existingFiles.contains(song.remoteFilename) { continue }
                 
                 
                 if song.artworkData != nil {
                     if artworkIndex < artworkInfo.count {
                         let info = artworkInfo[artworkIndex]
                         let artworkData = song.artworkData!
                         
                         let artworkRelativePath = info.artworkHash
                         let pathComponents = artworkRelativePath.components(separatedBy: "/")
                         let fileName = pathComponents.last ?? "unknown"
                         let artworkPath = "/iTunes_Control/iTunes/Artwork/Originals/\(artworkRelativePath)"
                         
                         let tempArtwork = FileManager.default.temporaryDirectory.appendingPathComponent(fileName)
                         try? artworkData.write(to: tempArtwork)
                         
                         let semArt = DispatchSemaphore(value: 0)
                         self.uploadFileToDevice(localURL: tempArtwork, remotePath: artworkPath) { _ in semArt.signal() }
                         semArt.wait()
                         try? FileManager.default.removeItem(at: tempArtwork)
                         
                         artworkIndex += 1
                     }
                 }
            }

            
            progress("Uploading database...")
            Logger.shared.log("[DeviceManager] Step 5: Uploading database (Atomic Upgrade)")
            
            let tempDBPath = "/iTunes_Control/iTunes/MediaLibrary.sqlitedb.temp"
            let finalDBPath = "/iTunes_Control/iTunes/MediaLibrary.sqlitedb"
            let shmPath = "/iTunes_Control/iTunes/MediaLibrary.sqlitedb-shm"
            let walPath = "/iTunes_Control/iTunes/MediaLibrary.sqlitedb-wal"
            
            
            let semUploadDB = DispatchSemaphore(value: 0)
            var dbUploadSuccess = false
            self.uploadFileToDevice(localURL: dbURL, remotePath: tempDBPath) { success in
                dbUploadSuccess = success
                semUploadDB.signal()
            }
            semUploadDB.wait()
            
            if !dbUploadSuccess {
                Logger.shared.log("[DeviceManager] ERROR: Failed to upload temp database")
                DispatchQueue.main.async { completion(false) }
                return
            }
            
            
            var afcSwap: AfcClientHandle?
            afc_client_connect(self.provider, &afcSwap)
            
            guard afcSwap != nil else {
                Logger.shared.log("[DeviceManager] ERROR: Failed to connect AFC for atomic swap")
                DispatchQueue.main.async { completion(false) }
                return
            }
            
            
            afc_remove_path(afcSwap, shmPath)
            afc_remove_path(afcSwap, walPath)
            
            
            afc_remove_path(afcSwap, finalDBPath)
            
            
            let renameErr = afc_rename_path(afcSwap, tempDBPath, finalDBPath)
            
            if renameErr != nil {
                Logger.shared.log("[DeviceManager] ERROR: Failed to rename database (Error: \(renameErr!))")
                 
                 afc_remove_path(afcSwap, tempDBPath)
                 afc_client_free(afcSwap)
                 DispatchQueue.main.async { completion(false) }
                 return
            }
            
            Logger.shared.log("[DeviceManager] Database swapped successfully.")
            afc_client_free(afcSwap)
            
            if !dbUploadSuccess {
                Logger.shared.log("[DeviceManager] ERROR: Failed to upload database")
                DispatchQueue.main.async { completion(false) }
                return
            }
            
            
            progress("Finalizing...")
            self.sendSyncFinishedNotification()
            
            progress("Playlist '\(playlistName ?? "Unknown")' updated!")
            Logger.shared.log("[DeviceManager] Playlist injection complete!")
            DispatchQueue.main.async { completion(true) }
        }
    }
    
    func fetchPlaylists(completion: @escaping ([(name: String, pid: Int64)]) -> Void) {
        let dbPath = "/iTunes_Control/iTunes/MediaLibrary.sqlitedb"
        
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self = self, self.heartbeatReady else {
                DispatchQueue.main.async { completion([]) }
                return
            }
            
            var success = false
            var dbData: Data?
            let sem = DispatchSemaphore(value: 0)
            
            self.downloadFileFromDevice(remotePath: dbPath) { data in
                if let data = data {
                    dbData = data
                    success = true
                }
                sem.signal()
            }
            sem.wait()
            
            if !success {
                Logger.shared.log("[DeviceManager] Failed to download DB for playlist fetch")
                DispatchQueue.main.async { completion([]) }
                return
            }
            
            
            let tempDB = FileManager.default.temporaryDirectory.appendingPathComponent("PlaylistFetch.sqlitedb")
            do {
                try dbData?.write(to: tempDB)
            } catch {
                 DispatchQueue.main.async { completion([]) }
                 return
            }
            
            let playlists = MediaLibraryBuilder.extractPlaylists(fromDbPath: tempDB.path)
            try? FileManager.default.removeItem(at: tempDB)
            
            DispatchQueue.main.async { completion(playlists) }
        }
    }
    
    
    
    func injectRingtones(ringtones: [SongMetadata], progress: @escaping (String) -> Void, completion: @escaping (Bool) -> Void) {
        Logger.shared.log("[DeviceManager] injectRingtones called with \(ringtones.count) ringtones")
        
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self = self else { return }
            
            
            // ── Step 1: Load existing Ringtones.plist (merge, don't overwrite) ──
            progress("Preparing ringtones...")
            Logger.shared.log("[DeviceManager] Downloading existing Ringtones.plist")

            var rootDict: [String: Any] = [:]
            var ringtonesDict: [String: Any] = [:]

            let plistSem = DispatchSemaphore(value: 0)
            self.downloadFileFromDevice(remotePath: "/iTunes_Control/Ringtones/Ringtones.plist") { data in
                if let data = data {
                    if let dict = try? PropertyListSerialization.propertyList(from: data, options: .mutableContainersAndLeaves, format: nil) as? [String: Any] {
                        rootDict = dict
                        ringtonesDict = (dict["Ringtones"] as? [String: Any]) ?? [:]
                        Logger.shared.log("[DeviceManager] Loaded existing plist with \(ringtonesDict.count) entries")
                    }
                }
                plistSem.signal()
            }
            plistSem.wait()

            // ── Step 2: Ensure /iTunes_Control/Ringtones exists ──────────────
            var afcDir: AfcClientHandle?
            afc_client_connect(self.provider, &afcDir)
            if afcDir != nil {
                afc_make_directory(afcDir, "/iTunes_Control/Ringtones")
                afc_client_free(afcDir)
            }

            // ── Step 3: Upload each .m4r and build the plist entries ─────────
            // Confirmed by reversing a real device DB exported via 3uTools:
            // MediaLibrary.sqlitedb has ZERO ringtone rows (media_type 16384).
            // iOS reads ringtones exclusively from Ringtones.plist + the file.
            // GUID must be a 16-char uppercase hex string (e.g. "E3773EA9BBA24B35").
            progress("Uploading ringtones...")

            for ringtone in ringtones {
                let remotePath = "/iTunes_Control/Ringtones/\(ringtone.remoteFilename)"

                let uploadSem = DispatchSemaphore(value: 0)
                var uploadOK = false
                self.uploadFileToDevice(localURL: ringtone.localURL, remotePath: remotePath) { s in
                    uploadOK = s
                    uploadSem.signal()
                }
                uploadSem.wait()

                if uploadOK {
                    Logger.shared.log("[DeviceManager] Uploaded: \(ringtone.remoteFilename)")
                } else {
                    Logger.shared.log("[DeviceManager] WARNING: Failed to upload \(ringtone.remoteFilename)")
                }

                // PID and GUID match the format Apple/3uTools uses
                let pid  = SongMetadata.generatePersistentId()
                let guid = String(format: "%016llX", SongMetadata.generatePersistentId())

                let entry: [String: Any] = [
                    "Name":              ringtone.title,
                    "Total Time":        ringtone.durationMs,   // real duration ms
                    "PID":               pid,
                    "Protected Content": false,
                    "GUID":              guid
                ]
                ringtonesDict[ringtone.remoteFilename] = entry
                Logger.shared.log("[DeviceManager] Plist entry: \(ringtone.remoteFilename) PID=\(pid) GUID=\(guid)")
            }

            // ── Step 4: Upload merged Ringtones.plist (binary format) ────────
            rootDict["Ringtones"] = ringtonesDict

            do {
                let tempDir  = FileManager.default.temporaryDirectory
                let plistData = try PropertyListSerialization.data(fromPropertyList: rootDict, format: .binary, options: 0)
                let tempPlist = tempDir.appendingPathComponent("Ringtones.plist")
                try plistData.write(to: tempPlist)

                let plistSem2 = DispatchSemaphore(value: 0)
                self.uploadFileToDevice(localURL: tempPlist, remotePath: "/iTunes_Control/Ringtones/Ringtones.plist") { _ in
                    plistSem2.signal()
                }
                plistSem2.wait()
                Logger.shared.log("[DeviceManager] Ringtones.plist uploaded (\(ringtonesDict.count) total entries)")
            } catch {
                Logger.shared.log("[DeviceManager] Failed to upload Ringtones.plist: \(error)")
            }

            progress("Done!")
            self.sendSyncFinishedNotification()
            DispatchQueue.main.async { completion(true) }
        }
    }
}


extension URL {
    static var documentsDirectory: URL {
        return FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
    }
}

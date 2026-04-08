import Foundation
import SwiftUI
import Combine

class Logger: ObservableObject {
    static let shared = Logger()
    
    @Published var logs: String = ""
    private var dateFormatter: DateFormatter
    
    
    private let logQueue = DispatchQueue(label: "com.edualexxis.MusicManager.logger")
    
    private init() {
        dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "HH:mm:ss.SSS"
        log("===========================================")
        log("Logger Initialized")
        log("===========================================")
    }
    
    func log(_ message: String) {
        let timestamp = dateFormatter.string(from: Date())
        let formattedMessage = "[\(timestamp)] \(message)"
        
        
        print(formattedMessage)
        
        
        logQueue.async {
            DispatchQueue.main.async {
                self.logs.append(formattedMessage + "\n")
            }
        }
    }
    
    func clear() {
        logQueue.async {
            DispatchQueue.main.async {
                self.logs = ""
            }
        }
    }
    
    func saveLogs() -> URL? {
        let fileManager = FileManager.default
        let logsDirectory = fileManager.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Logs", isDirectory: true)
        let fileURL = logsDirectory.appendingPathComponent("MusicManager_Logs.txt")
        
        do {
            if !fileManager.fileExists(atPath: logsDirectory.path) {
                try fileManager.createDirectory(at: logsDirectory, withIntermediateDirectories: true)
            }
            if fileManager.fileExists(atPath: fileURL.path) {
                try fileManager.removeItem(at: fileURL)
            }
            try logs.write(to: fileURL, atomically: true, encoding: .utf8)
            return fileURL
        } catch {
            print("Failed to save logs: \(error)")
            return nil
        }
    }
}

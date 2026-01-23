import Foundation
import SwiftUI
import Combine

class Logger: ObservableObject {
    static let shared = Logger()
    
    @Published var logs: String = ""
    private var dateFormatter: DateFormatter
    
    // We use a serial queue to ensure thread safety when appending logs
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
        
        // Print to Xcode console
        print(formattedMessage)
        
        // Append to in-app log buffer
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
        let timestamp = ISO8601DateFormatter().string(from: Date()).replacingOccurrences(of: ":", with: "-")
        let filename = "MusicManager_Logs_\(timestamp).txt"
        let fileURL = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0].appendingPathComponent(filename)
        
        do {
            try logs.write(to: fileURL, atomically: true, encoding: .utf8)
            return fileURL
        } catch {
            print("Failed to save logs: \(error)")
            return nil
        }
    }
}

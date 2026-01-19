import Foundation
import AVFoundation
import Foundation
import AVFoundation
import SwiftUI
import Combine

class VideoManager: ObservableObject {
    @Published var videos: [Video] = []
    @Published var isLoading = false
    
    init() {
        // Defer loading to onAppear to avoid blocking app launch
    }
    
    private func setupDocumentsDirectory() {
        let fileManager = FileManager.default
        guard let documentsURL = fileManager.urls(for: .documentDirectory, in: .userDomainMask).first else { return }
        
        // Write a persistent file so the folder appears in Files app
        let readmeURL = documentsURL.appendingPathComponent("README.txt")
        print("Seting up Documents Directory at: \(documentsURL.path)")
        if !fileManager.fileExists(atPath: readmeURL.path) {
            let content = "Put your .mp4, .mov, .m4v video files in this folder to play them in Vid."
            do {
                try content.write(to: readmeURL, atomically: true, encoding: .utf8)
                print("Successfully wrote README.txt to \(readmeURL.path)")
            } catch {
                print("Failed to write README.txt: \(error)")
            }
        } else {
            print("README.txt already exists at \(readmeURL.path)")
        }
    }
    
    func loadVideos() {
        guard !isLoading else { return }
        
        // setupDocumentsDirectory() // Handled in VidApp.init to allow faster launch
        
        isLoading = true
        videos = []
        
        guard let directory = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first else {
            isLoading = false
            return
        }
        
        let fileManager = FileManager.default
        
        Task {
            do {
                let resourceKeys: [URLResourceKey] = [.nameKey, .isDirectoryKey]
                let enumerator = fileManager.enumerator(at: directory, includingPropertiesForKeys: resourceKeys, options: [.skipsHiddenFiles])
                
                var loadedVideos: [Video] = []
                
                while let fileURL = enumerator?.nextObject() as? URL {
                    let resourceValues = try fileURL.resourceValues(forKeys: Set(resourceKeys))
                    if resourceValues.isDirectory == true { continue }
                    
                    let validExtensions = ["mp4", "mov", "m4v"]
                    if validExtensions.contains(fileURL.pathExtension.lowercased()) {
                        let asset = AVURLAsset(url: fileURL)
                        do {
                            let durationTime = try await asset.load(.duration)
                            let duration = CMTimeGetSeconds(durationTime)
                            let video = Video(name: fileURL.deletingPathExtension().lastPathComponent, url: fileURL, duration: duration)
                            loadedVideos.append(video)
                        } catch {
                            print("Failed to load duration for \(fileURL.lastPathComponent)")
                        }
                    }
                }
                
                let finalVideos = loadedVideos.sorted { $0.name < $1.name }
                await MainActor.run {
                    self.videos = finalVideos
                    self.isLoading = false
                }
            } catch {
                print("Error enumerating files: \(error)")
                await MainActor.run {
                    self.isLoading = false
                }
            }
        }
        }

    
    func importFiles(_ urls: [URL]) {
        guard let documentsURL = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first else { return }
        
        for url in urls {
            guard url.startAccessingSecurityScopedResource() else { continue }
            defer { url.stopAccessingSecurityScopedResource() }
            
            let destinationURL = documentsURL.appendingPathComponent(url.lastPathComponent)
            
            do {
                if FileManager.default.fileExists(atPath: destinationURL.path) {
                    try FileManager.default.removeItem(at: destinationURL)
                }
                try FileManager.default.copyItem(at: url, to: destinationURL)
            } catch {
                print("Failed to import file: \(error)")
            }
        }
        
        loadVideos()
    }
}

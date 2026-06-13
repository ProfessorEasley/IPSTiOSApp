//
//  ImagePicker.swift
//  IPSTStyleApp
//
//  Created by EXPO on 12/5/25.
//

import SwiftUI
import PhotosUI
import UniformTypeIdentifiers

enum PhotoLibraryMediaFilter {
    case images
    case imagesAndVideos
}

// MARK: - Photo Library Picker (iOS 16+)
struct PhotoLibraryPicker: UIViewControllerRepresentable {
    @Binding var selectedImage: UIImage?
    var selectedVideoURL: Binding<URL?>?
    var mediaFilter: PhotoLibraryMediaFilter = .images

    @Environment(\.dismiss) private var dismiss
    
    func makeUIViewController(context: Context) -> PHPickerViewController {
        var config = PHPickerConfiguration()
        switch mediaFilter {
        case .images:
            config.filter = .images
        case .imagesAndVideos:
            config.filter = .any(of: [.images, .videos])
        }
        config.selectionLimit = 1
        
        let picker = PHPickerViewController(configuration: config)
        picker.delegate = context.coordinator
        return picker
    }
    
    func updateUIViewController(_ uiViewController: PHPickerViewController, context: Context) {}
    
    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }
    
    class Coordinator: NSObject, PHPickerViewControllerDelegate {
        let parent: PhotoLibraryPicker
        
        init(_ parent: PhotoLibraryPicker) {
            self.parent = parent
        }
        
        func picker(_ picker: PHPickerViewController, didFinishPicking results: [PHPickerResult]) {
            parent.dismiss()
            print("Picked results count:", results.count)
            
            guard let provider = results.first?.itemProvider else {
                print("Could not load item provider")
                return
            }

            if provider.hasItemConformingToTypeIdentifier(UTType.movie.identifier) {
                provider.loadFileRepresentation(forTypeIdentifier: UTType.movie.identifier) { [weak self] url, error in
                    if let error {
                        print("Video load error:", error)
                    }

                    guard let url else { return }

                    let fileName = "\(UUID().uuidString).\(url.pathExtension.isEmpty ? "mov" : url.pathExtension)"
                    let destinationURL = FileManager.default.temporaryDirectory.appendingPathComponent(fileName)

                    do {
                        if FileManager.default.fileExists(atPath: destinationURL.path) {
                            try FileManager.default.removeItem(at: destinationURL)
                        }
                        try FileManager.default.copyItem(at: url, to: destinationURL)

                        DispatchQueue.main.async {
                            self?.parent.selectedImage = nil
                            self?.parent.selectedVideoURL?.wrappedValue = destinationURL
                        }
                    } catch {
                        print("Video copy error:", error)
                    }
                }
                return
            }

            guard provider.canLoadObject(ofClass: UIImage.self) else {
                print("Could not load UIImage")
                return
            }
            
            provider.loadObject(ofClass: UIImage.self) { [weak self] image, error in
                    DispatchQueue.main.async {
                        if let error = error {
                            print("Load error:", error)
                        }
                        print("Loaded image:", image as Any)
                        self?.parent.selectedImage = image as? UIImage
                        self?.parent.selectedVideoURL?.wrappedValue = nil
                    }
                }
        }
    }
}

// MARK: - Camera Picker
import SwiftUI
import UIKit

struct CameraPicker: UIViewControllerRepresentable {
    @Binding var selectedImage: UIImage?
    @Environment(\.dismiss) private var dismiss

    static var isAvailable: Bool {
        UIImagePickerController.isSourceTypeAvailable(.camera)
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    func makeUIViewController(context: Context) -> UIImagePickerController {
        let picker = UIImagePickerController()
        picker.sourceType = .camera
        picker.allowsEditing = false
        picker.cameraCaptureMode = .photo
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(_ uiViewController: UIImagePickerController, context: Context) {}

    class Coordinator: NSObject, UIImagePickerControllerDelegate, UINavigationControllerDelegate {
        let parent: CameraPicker

        init(_ parent: CameraPicker) {
            self.parent = parent
        }

        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
            parent.dismiss()
        }

        func imagePickerController(
            _ picker: UIImagePickerController,
            didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey : Any]
        ) {
            if let image = info[.originalImage] as? UIImage {
                parent.selectedImage = image
            }
            parent.dismiss()
        }
    }
}
//// MARK: - Camera Availability Check
//extension CameraPicker {
//    static var isAvailable: Bool {
//        UIImagePickerController.isSourceTypeAvailable(.camera)
//    }
//}

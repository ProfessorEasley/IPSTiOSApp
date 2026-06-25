// PhotoLibraryPicker.swift
import SwiftUI
import PhotosUI

enum MediaFilter {
    case imagesOnly
    case videosOnly
    case imagesAndVideos
}

struct PhotoLibraryPicker: UIViewControllerRepresentable {
    @Binding var selectedImage: UIImage?
    @Binding var selectedVideoURL: URL?
    var mediaFilter: MediaFilter = .imagesAndVideos

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    func makeUIViewController(context: Context) -> PHPickerViewController {
        var config = PHPickerConfiguration(photoLibrary: .shared())
        config.selectionLimit = 1
        switch mediaFilter {
        case .imagesOnly:
            config.filter = .images
        case .videosOnly:
            config.filter = .videos
        case .imagesAndVideos:
            config.filter = .any(of: [.images, .videos])
        }
        let picker = PHPickerViewController(configuration: config)
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(_ uiViewController: PHPickerViewController, context: Context) {}

    class Coordinator: NSObject, PHPickerViewControllerDelegate {
        let parent: PhotoLibraryPicker

        init(_ parent: PhotoLibraryPicker) {
            self.parent = parent
        }

        func picker(_ picker: PHPickerViewController, didFinishPicking results: [PHPickerResult]) {
            picker.dismiss(animated: true)
            guard let result = results.first else { return }
            let provider = result.itemProvider

            if provider.canLoadObject(ofClass: UIImage.self) {
                provider.loadObject(ofClass: UIImage.self) { object, _ in
                    DispatchQueue.main.async {
                        self.parent.selectedImage = object as? UIImage
                        self.parent.selectedVideoURL = nil
                    }
                }
            } else if provider.hasItemConformingToTypeIdentifier("public.movie") {
                provider.loadFileRepresentation(forTypeIdentifier: "public.movie") { url, _ in
                    guard let url = url else { return }
                    let temp = FileManager.default.temporaryDirectory
                        .appendingPathComponent(url.lastPathComponent)
                    try? FileManager.default.removeItem(at: temp)
                    try? FileManager.default.copyItem(at: url, to: temp)
                    DispatchQueue.main.async {
                        self.parent.selectedVideoURL = temp
                        self.parent.selectedImage = nil
                    }
                }
            }
        }
    }
}

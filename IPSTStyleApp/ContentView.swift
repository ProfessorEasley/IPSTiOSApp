//
//  ContentView.swift
//  IPSTStyleApp
//
//  Created by EXPO on 12/4/25.
//

import SwiftUI
import UIKit
import AVKit

struct ContentView: View {
    @State private var sourceImage: UIImage?
    @State private var sourceVideoURL: URL?
    @State private var targetImage: UIImage?
    @State private var targetVideoURL: URL?
    @State private var stylizedImage: UIImage?
    @State private var isProcessing = false
    @State private var isSaving = false
    @State private var showSourceLibrary = false
    @State private var showSourceCamera = false
    @State private var showTargetLibrary = false
    @State private var showTargetCamera = false
    @State private var showResultScreen = false
    @State private var showCameraError = false
    @State private var showError = false
    @State private var showSaveToast = false
    @State private var errorMessage: String?
    @State private var pulseTransferIndicator = false
    @State private var imageSaver: ImageSaver?

    @StateObject private var styleService = StyleTransferService()

    private var canApplyTransfer: Bool {
        (sourceImage != nil || sourceVideoURL != nil)
            && (targetImage != nil || targetVideoURL != nil)
            && !isProcessing
    }

    private var canSave: Bool {
        stylizedImage != nil && !isSaving && !isProcessing
    }

    var body: some View {
        ZStack {
            LinearGradient(
                colors: [Color(hex: "111326"), Color(hex: "171b35"), Color(hex: "10121f")],
                startPoint: .top,
                endPoint: .bottom
            )
            .ignoresSafeArea()

            ScrollView(showsIndicators: false) {
                VStack(spacing: 22) {
                    headerView

                    ImageStepView(
                        stepLabel: "1. SOURCE IMAGE OR VIDEO",
                        stepColor: Color(hex: "ff3f8f"),
                        subtitle: "Media to Style",
                        image: sourceImage,
                        videoURL: sourceVideoURL,
                        placeholderIcon: "paintpalette.fill",
                        placeholderText: "Choose source image or video",
                        libraryTitle: "Choose Media",
                        onLibraryTap: { showSourceLibrary = true },
                        onCameraTap: { openCamera(for: .source) }
                    )

                    transferIndicator

                    ImageStepView(
                        stepLabel: "2. TARGET STYLE IMAGE OR VIDEO",
                        stepColor: Color(hex: "a78bfa"),
                        subtitle: "Style Reference",
                        image: targetImage,
                        videoURL: targetVideoURL,
                        placeholderIcon: "photo.on.rectangle.angled",
                        placeholderText: "Choose image or video",
                        libraryTitle: "Choose Media",
                        onLibraryTap: { showTargetLibrary = true },
                        onCameraTap: { openCamera(for: .target) }
                    )

                    primaryActionButton
                    resultSection
                    statusIndicator
                }
                .padding(.horizontal, 18)
                .padding(.top, 18)
                .padding(.bottom, 24)
            }
            .safeAreaInset(edge: .top) {
                Color.clear.frame(height: 1)
            }

            if showSaveToast {
                SavedToast()
                    .padding(.horizontal, 24)
                    .padding(.bottom, 28)
                    .frame(maxHeight: .infinity, alignment: .bottom)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                    .zIndex(1)
            }
        }
        .sheet(isPresented: $showSourceLibrary) {
            PhotoLibraryPicker(
                selectedImage: $sourceImage,
                selectedVideoURL: $sourceVideoURL,
                mediaFilter: .imagesAndVideos
            )
        }
        .sheet(isPresented: $showTargetLibrary) {
            PhotoLibraryPicker(
                selectedImage: $targetImage,
                selectedVideoURL: $targetVideoURL,
                mediaFilter: .imagesAndVideos
            )
        }
        .fullScreenCover(isPresented: $showSourceCamera) {
            CameraPicker(selectedImage: $sourceImage)
                .ignoresSafeArea()
        }
        .fullScreenCover(isPresented: $showTargetCamera) {
            CameraPicker(selectedImage: $targetImage)
                .ignoresSafeArea()
        }
        .fullScreenCover(isPresented: $showResultScreen) {
            if let sourceImage, let stylizedImage {
                ResultFullScreenView(
                    originalImage: sourceImage,
                    stylizedImage: stylizedImage,
                    showSaveToast: $showSaveToast,
                    onSave: saveToGallery,
                    onCancel: { showResultScreen = false }
                )
            }
        }
        .alert("Camera Unavailable", isPresented: $showCameraError) {
            Button("OK", role: .cancel) { }
        } message: {
            Text("Camera is not available in the simulator. Use Library instead.")
        }
        .alert("Style Transfer Error", isPresented: $showError) {
            Button("OK", role: .cancel) { }
        } message: {
            Text(errorMessage ?? "An unknown error occurred")
        }
        .onChange(of: sourceImage) {
            stylizedImage = nil
            if sourceImage != nil {
                sourceVideoURL = nil
            }
        }
        .onChange(of: sourceVideoURL) {
            stylizedImage = nil
        }
        .onChange(of: targetImage) {
            stylizedImage = nil
            if targetImage != nil {
                targetVideoURL = nil
            }
        }
        .onChange(of: targetVideoURL) {
            stylizedImage = nil
        }
        .onAppear {
            withAnimation(.easeInOut(duration: 1.2).repeatForever(autoreverses: true)) {
                pulseTransferIndicator = true
            }
        }
    }

    private var headerView: some View {
        VStack(spacing: 8) {
            HStack(spacing: 10) {
                Image(systemName: "wand.and.stars")
                    .font(.system(size: 30, weight: .semibold))
                    .foregroundStyle(
                        LinearGradient(
                            colors: [Color(hex: "ff3f8f"), Color(hex: "a78bfa")],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )

                Text("IPST Style")
                    .font(.system(size: 30, weight: .bold, design: .rounded))
                    .foregroundColor(.white)
            }

            Text("Transfer color to images or videos")
                .font(.system(size: 15, weight: .medium))
                .foregroundColor(Color(hex: "94a3b8"))
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 8)
        .padding(.bottom, 4)
    }

    private var transferIndicator: some View {
        VStack(spacing: 8) {
            Image(systemName: "arrow.down.circle.fill")
                .font(.system(size: 34, weight: .semibold))
                .foregroundStyle(
                    LinearGradient(
                        colors: [Color(hex: "ff3f8f"), Color(hex: "a78bfa")],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
                .scaleEffect(pulseTransferIndicator ? 1.08 : 0.96)
                .opacity(pulseTransferIndicator ? 1.0 : 0.72)

            Text("Transfer Color")
                .font(.system(size: 14, weight: .semibold))
                .foregroundColor(Color(hex: "cbd5e1"))
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 2)
    }

    private var primaryActionButton: some View {
        VStack(spacing: 8) {
            Button(action: applyStyleTransfer) {
                HStack(spacing: 10) {
                    Image(systemName: "wand.and.stars")
                        .font(.system(size: 19, weight: .bold))

                    Text(isProcessing ? "APPLYING COLOR TRANSFER" : primaryActionTitle)
                        .font(.system(size: 16, weight: .bold))
                }
                .foregroundColor(.white)
                .frame(maxWidth: .infinity)
                .frame(height: 60)
                .background(
                    LinearGradient(
                        colors: [Color(hex: "ff3f8f"), Color(hex: "5b21b6")],
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                )
                .clipShape(RoundedRectangle(cornerRadius: 18))
                .shadow(color: Color(hex: "ff3f8f").opacity(canApplyTransfer ? 0.35 : 0.0), radius: 16, x: 0, y: 8)
            }
            .disabled(!canApplyTransfer)
            .opacity(canApplyTransfer ? 1.0 : 0.42)

            Text("Select source and target media to enable")
                .font(.system(size: 13, weight: .medium))
                .foregroundColor(Color(hex: "94a3b8"))
                .opacity(canApplyTransfer ? 0.0 : 1.0)
                .frame(height: 18)
        }
    }

    private var resultSection: some View {
        HStack(spacing: 14) {
            VStack(alignment: .leading, spacing: 6) {
                Text(resultTitle)
                    .font(.system(size: 16, weight: .bold))
                    .foregroundColor(.white)

                Text(resultSubtitle)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundColor(Color(hex: "94a3b8"))
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 12)

            Button(action: saveToGallery) {
                HStack(spacing: 7) {
                    Image(systemName: "square.and.arrow.down")
                        .font(.system(size: 14, weight: .bold))

                    Text(isSaving ? "Saving" : "Save")
                        .font(.system(size: 14, weight: .bold))
                }
                .foregroundColor(Color.white.opacity(canSave ? 1.0 : 0.5))
                .padding(.horizontal, 14)
                .frame(height: 42)
                .background(Color.white.opacity(0.08))
                .clipShape(RoundedRectangle(cornerRadius: 12))
            }
            .disabled(!canSave)
            .opacity(canSave ? 1.0 : 0.5)
        }
        .padding(18)
        .background(Color.white.opacity(0.055))
        .overlay(
            RoundedRectangle(cornerRadius: 18)
                .stroke(Color.white.opacity(0.1), lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 18))
    }

    private var statusIndicator: some View {
        HStack(spacing: 8) {
            Circle()
                .fill(Color(hex: "22c55e"))
                .frame(width: 8, height: 8)

            Text("Model Ready")
                .font(.system(size: 12, weight: .medium))
                .foregroundColor(Color(hex: "94a3b8"))
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 2)
    }

    private var primaryActionTitle: String {
        sourceVideoURL == nil && targetVideoURL == nil ? "APPLY COLOR TRANSFER" : "APPLY TO VIDEO"
    }

    private var resultTitle: String {
        sourceVideoURL == nil && targetVideoURL == nil ? "Result will appear here" : "Video media selected"
    }

    private var resultSubtitle: String {
        sourceVideoURL == nil && targetVideoURL == nil
            ? "You can save or share the result"
            : "Frame-by-frame video transfer still needs the video backend"
    }

    private func openCamera(for slot: ImageSlot) {
        guard CameraPicker.isAvailable else {
            showCameraError = true
            return
        }

        switch slot {
        case .source:
            showSourceCamera = true
        case .target:
            showTargetCamera = true
        }
    }

    private func applyStyleTransfer() {
        if sourceVideoURL != nil || targetVideoURL != nil {
            errorMessage = "Source and target video selection is ready. To apply style to MP4s, add the AVFoundation frame-by-frame export pipeline around the Core ML model."
            showError = true
            return
        }

        guard let sourceImage, let targetImage else { return }

        isProcessing = true

        Task {
            do {
                let result = try await styleService.applyStyle(
                    source: targetImage,
                    target: sourceImage
                )

                await MainActor.run {
                    stylizedImage = result
                    isProcessing = false
                    showResultScreen = true
                }
            } catch {
                await MainActor.run {
                    errorMessage = error.localizedDescription
                    showError = true
                    isProcessing = false
                }
            }
        }
    }

    private func saveToGallery() {
        guard let image = stylizedImage else { return }

        isSaving = true

        let saver = ImageSaver()
        imageSaver = saver
        saver.onSuccess = {
            DispatchQueue.main.async {
                isSaving = false
                imageSaver = nil
                showImageSavedToast()
            }
        }
        saver.onError = { error in
            DispatchQueue.main.async {
                isSaving = false
                imageSaver = nil
                errorMessage = error.localizedDescription
                showError = true
            }
        }

        saver.saveImage(image)
    }

    private func showImageSavedToast() {
        withAnimation(.spring(response: 0.35, dampingFraction: 0.9)) {
            showSaveToast = true
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
            withAnimation(.easeOut(duration: 0.25)) {
                showSaveToast = false
            }
        }
    }
}

private enum ImageSlot {
    case source
    case target
}

private struct ImageStepView: View {
    let stepLabel: String
    let stepColor: Color
    let subtitle: String
    let image: UIImage?
    let videoURL: URL?
    let placeholderIcon: String
    let placeholderText: String
    let libraryTitle: String
    let onLibraryTap: () -> Void
    let onCameraTap: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text(stepLabel)
                    .font(.system(size: 13, weight: .bold))
                    .foregroundColor(stepColor)

                Text(subtitle)
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(Color(hex: "94a3b8"))
            }

            ImageCard(
                image: image,
                videoURL: videoURL,
                placeholderIcon: placeholderIcon,
                placeholderText: placeholderText
            )

            HStack(spacing: 12) {
                GradientIconButton(
                    title: libraryTitle,
                    systemImage: "photo.stack",
                    colors: [Color(hex: "667eea"), Color(hex: "764ba2")],
                    action: onLibraryTap
                )

                GradientIconButton(
                    title: "Camera",
                    systemImage: "camera.fill",
                    colors: [Color(hex: "ff5fa2"), Color(hex: "e11d48")],
                    action: onCameraTap
                )
                .opacity(CameraPicker.isAvailable ? 1.0 : 0.55)
            }
        }
    }
}

private struct ImageCard: View {
    let image: UIImage?
    let videoURL: URL?
    let placeholderIcon: String
    let placeholderText: String

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 20)
                .fill(Color.white.opacity(0.055))
                .overlay(
                    RoundedRectangle(cornerRadius: 20)
                        .stroke(Color.white.opacity(0.1), lineWidth: 1)
                )

            if let image {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
                    .frame(maxWidth: .infinity)
                    .frame(height: 210)
                    .clipShape(RoundedRectangle(cornerRadius: 16))
                    .padding(8)
            } else if let videoURL {
                VideoPlayer(player: AVPlayer(url: videoURL))
                    .frame(maxWidth: .infinity)
                    .frame(height: 210)
                    .clipShape(RoundedRectangle(cornerRadius: 16))
                    .padding(8)
                    .overlay(alignment: .topLeading) {
                        Label("Video", systemImage: "video.fill")
                            .font(.system(size: 12, weight: .bold))
                            .foregroundColor(.white)
                            .padding(.horizontal, 10)
                            .frame(height: 30)
                            .background(Color.black.opacity(0.62))
                            .clipShape(Capsule())
                            .padding(14)
                    }
            } else {
                VStack(spacing: 12) {
                    Image(systemName: placeholderIcon)
                        .font(.system(size: 42, weight: .light))
                        .foregroundColor(Color.white.opacity(0.28))

                    Text(placeholderText)
                        .font(.system(size: 14, weight: .medium))
                        .foregroundColor(Color(hex: "64748b"))
                }
            }
        }
        .frame(maxWidth: .infinity)
        .frame(height: 226)
    }
}

private struct GradientIconButton: View {
    let title: String
    let systemImage: String
    let colors: [Color]
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 9) {
                Image(systemName: systemImage)
                    .font(.system(size: 17, weight: .semibold))

                Text(title)
                    .font(.system(size: 15, weight: .semibold))
            }
            .foregroundColor(.white)
            .frame(maxWidth: .infinity)
            .frame(height: 52)
            .background(
                LinearGradient(
                    colors: colors,
                    startPoint: .leading,
                    endPoint: .trailing
                )
            )
            .clipShape(RoundedRectangle(cornerRadius: 15))
        }
    }
}

private struct ResultFullScreenView: View {
    let originalImage: UIImage
    let stylizedImage: UIImage
    @Binding var showSaveToast: Bool
    let onSave: () -> Void
    let onCancel: () -> Void

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            VStack(spacing: 20) {
                HStack {
                    Button(action: onCancel) {
                        Text("Cancel")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundColor(.white)
                            .padding(.horizontal, 16)
                            .padding(.vertical, 10)
                            .background(Color.white.opacity(0.15))
                            .clipShape(Capsule())
                    }

                    Spacer()

                    Text("Preview")
                        .font(.system(size: 18, weight: .bold))
                        .foregroundColor(.white)

                    Spacer()

                    Color.clear
                        .frame(width: 72, height: 36)
                }
                .padding(.horizontal)
                .padding(.top, 8)

                Spacer()

                BeforeAfterComparisonView(
                    originalImage: originalImage,
                    stylizedImage: stylizedImage,
                    cornerRadius: 24
                )
                .padding(.horizontal, 16)
                .padding(.vertical, 8)

                Spacer()

                HStack(spacing: 12) {
                    Button(action: onCancel) {
                        Text("Cancel")
                            .font(.system(size: 16, weight: .bold))
                            .foregroundColor(.white)
                            .frame(maxWidth: .infinity)
                            .frame(height: 54)
                            .background(Color.white.opacity(0.12))
                            .clipShape(RoundedRectangle(cornerRadius: 14))
                    }

                    Button(action: onSave) {
                        Text("Save")
                            .font(.system(size: 16, weight: .bold))
                            .foregroundColor(.white)
                            .frame(maxWidth: .infinity)
                            .frame(height: 54)
                            .background(
                                LinearGradient(
                                    colors: [Color(hex: "11998e"), Color(hex: "38ef7d")],
                                    startPoint: .leading,
                                    endPoint: .trailing
                                )
                            )
                            .clipShape(RoundedRectangle(cornerRadius: 14))
                    }
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 28)
            }

            if showSaveToast {
                SavedToast()
                    .padding(.horizontal, 24)
                    .padding(.bottom, 34)
                    .frame(maxHeight: .infinity, alignment: .bottom)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                    .zIndex(1)
            }
        }
    }
}

private struct BeforeAfterComparisonView: View {
    let originalImage: UIImage
    let stylizedImage: UIImage
    let cornerRadius: CGFloat

    @State private var dividerPosition: CGFloat = 0.5

    var body: some View {
        GeometryReader { geometry in
            let fittedSize = fittedImageSize(
                imageSize: originalImage.size,
                availableSize: geometry.size
            )

            ZStack {
                if fittedSize.width > 0 && fittedSize.height > 0 {
                    comparisonImage(size: fittedSize)
                }
            }
            .frame(width: geometry.size.width, height: geometry.size.height)
        }
    }

    private func comparisonImage(size: CGSize) -> some View {
        let dividerX = size.width * dividerPosition

        return ZStack(alignment: .leading) {
            Image(uiImage: stylizedImage)
                .resizable()
                .scaledToFill()
                .frame(width: size.width, height: size.height)
                .clipped()

            Image(uiImage: originalImage)
                .resizable()
                .scaledToFill()
                .frame(width: size.width, height: size.height)
                .clipped()
                .mask(alignment: .leading) {
                    Rectangle()
                        .frame(width: dividerX, height: size.height)
                }

            divider(height: size.height)
                .position(x: dividerX, y: size.height / 2)
        }
        .frame(width: size.width, height: size.height)
        .clipShape(RoundedRectangle(cornerRadius: cornerRadius))
        .contentShape(Rectangle())
        .gesture(
            DragGesture(minimumDistance: 0)
                .onChanged { value in
                    dividerPosition = min(max(value.location.x / size.width, 0), 1)
                }
        )
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func divider(height: CGFloat) -> some View {
        ZStack {
            Rectangle()
                .fill(Color.white)
                .frame(width: 3, height: height)
                .shadow(color: .black.opacity(0.35), radius: 6, x: 0, y: 0)

            Circle()
                .fill(Color.white)
                .frame(width: 42, height: 42)
                .shadow(color: .black.opacity(0.35), radius: 8, x: 0, y: 3)
                .overlay(
                    HStack(spacing: 2) {
                        Image(systemName: "chevron.left")
                        Image(systemName: "chevron.right")
                    }
                    .font(.system(size: 12, weight: .bold))
                    .foregroundColor(Color(hex: "111326"))
                )
        }
        .accessibilityLabel("Before and after divider")
        .accessibilityHint("Drag left or right to compare the target and result image")
    }

    private func fittedImageSize(imageSize: CGSize, availableSize: CGSize) -> CGSize {
        guard imageSize.width > 0,
              imageSize.height > 0,
              availableSize.width > 0,
              availableSize.height > 0 else {
            return .zero
        }

        let scale = min(
            availableSize.width / imageSize.width,
            availableSize.height / imageSize.height
        )

        return CGSize(width: imageSize.width * scale, height: imageSize.height * scale)
    }
}

private struct SavedToast: View {
    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 18, weight: .semibold))
                .foregroundColor(Color(hex: "38ef7d"))

            Text("Image saved")
                .font(.system(size: 15, weight: .semibold))
                .foregroundColor(.white)
        }
        .padding(.horizontal, 16)
        .frame(height: 48)
        .background(Color.black.opacity(0.82))
        .overlay(
            RoundedRectangle(cornerRadius: 14)
                .stroke(Color.white.opacity(0.12), lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 14))
        .shadow(color: .black.opacity(0.35), radius: 14, x: 0, y: 8)
    }
}

private class ImageSaver: NSObject {
    var onSuccess: (() -> Void)?
    var onError: ((Error) -> Void)?

    func saveImage(_ image: UIImage) {
        UIImageWriteToSavedPhotosAlbum(image, self, #selector(saveCompleted), nil)
    }

    @objc private func saveCompleted(_ image: UIImage, didFinishSavingWithError error: Error?, contextInfo: UnsafeRawPointer) {
        if let error {
            onError?(error)
        } else {
            onSuccess?()
        }
    }
}

extension Color {
    init(hex: String) {
        let hex = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var int: UInt64 = 0
        Scanner(string: hex).scanHexInt64(&int)
        let a, r, g, b: UInt64
        switch hex.count {
        case 3:
            (a, r, g, b) = (255, (int >> 8) * 17, (int >> 4 & 0xF) * 17, (int & 0xF) * 17)
        case 6:
            (a, r, g, b) = (255, int >> 16, int >> 8 & 0xFF, int & 0xFF)
        case 8:
            (a, r, g, b) = (int >> 24, int >> 16 & 0xFF, int >> 8 & 0xFF, int & 0xFF)
        default:
            (a, r, g, b) = (255, 0, 0, 0)
        }
        self.init(
            .sRGB,
            red: Double(r) / 255,
            green: Double(g) / 255,
            blue: Double(b) / 255,
            opacity: Double(a) / 255
        )
    }
}

#Preview {
    ContentView()
}

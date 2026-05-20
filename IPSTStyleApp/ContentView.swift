//
//  ContentView.swift
//  IPSTStyleApp
//
//  Created by EXPO on 12/4/25.
//

import SwiftUI
import UIKit
import CoreML
import Vision

struct ContentView: View {
    @State private var selectedImage: UIImage?
    @State private var stylizedImage: UIImage?
    @State private var showPhotoLibrary = false
    @State private var showCamera = false
    @State private var modelLoaded = false
    @State private var isProcessing = false
    @State private var isSaving = false
    @State private var errorMessage: String?
    @State private var showError = false
    @State private var showSaveSuccess = false
    @State private var showResultScreen = false

    @StateObject private var styleService = StyleTransferService()

    var body: some View {
        NavigationView {
            ZStack {
                LinearGradient(
                    colors: [Color(hex: "1a1a2e"), Color(hex: "16213e")],
                    startPoint: .top,
                    endPoint: .bottom
                )
                .ignoresSafeArea()

                VStack(spacing: 24) {
                    headerView
                    imageDisplayArea
                    Spacer()
                    actionButtons
                    statusIndicator
                }
                .padding()
            }
            .navigationBarHidden(true)
        }
        .navigationViewStyle(.stack)
        .sheet(isPresented: $showPhotoLibrary) {
            PhotoLibraryPicker(selectedImage: $selectedImage)
        }
        .fullScreenCover(isPresented: $showCamera) {
            CameraPicker(selectedImage: $selectedImage)
                .ignoresSafeArea()
        }
        .fullScreenCover(isPresented: $showResultScreen) {
            if let originalImage = selectedImage, let stylizedImage = stylizedImage {
                ResultFullScreenView(
                    originalImage: originalImage,
                    stylizedImage: stylizedImage,
                    onSave: {
                        saveToGallery()
                        showResultScreen = false
                    },
                    onCancel: {
                        showResultScreen = false
                    }
                )
            } else {
                Color.black.ignoresSafeArea()
            }
        }
        .onChange(of: selectedImage) { _ in
            stylizedImage = nil
            showResultScreen = false
        }
        .alert("Style Transfer Error", isPresented: $showError) {
            Button("OK", role: .cancel) { }
        } message: {
            Text(errorMessage ?? "An unknown error occurred")
        }
        .alert("Saved!", isPresented: $showSaveSuccess) {
            Button("OK", role: .cancel) { }
        } message: {
            Text("Your stylized photo has been saved to the gallery.")
        }
        .onAppear {
            verifyModel()
        }
    }

    private var headerView: some View {
        VStack(spacing: 8) {
            HStack(spacing: 12) {
                Image(systemName: "wand.and.stars")
                    .font(.system(size: 32, weight: .medium))
                    .foregroundStyle(
                        LinearGradient(
                            colors: [Color(hex: "e94560"), Color(hex: "ff6b6b")],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )

                Text("IPST Style")
                    .font(.system(size: 28, weight: .bold, design: .rounded))
                    .foregroundColor(.white)
            }

            Text("Instant Photorealistic Style Transfer")
                .font(.system(size: 14, weight: .medium))
                .foregroundColor(Color.white.opacity(0.6))
        }
        .padding(.top, 20)
    }

    private var imageDisplayArea: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 20)
                .fill(Color.white.opacity(0.05))
                .overlay(
                    RoundedRectangle(cornerRadius: 20)
                        .stroke(Color.white.opacity(0.1), lineWidth: 1)
                )

            if let originalImage = selectedImage, let stylizedImage = stylizedImage {
                BeforeAfterComparisonView(
                    originalImage: originalImage,
                    stylizedImage: stylizedImage,
                    cornerRadius: 16
                )
                .padding(8)
            } else if let displayImage = selectedImage {
                Image(uiImage: displayImage)
                    .resizable()
                    .scaledToFit()
                    .clipShape(RoundedRectangle(cornerRadius: 16))
                    .padding(8)
            } else if selectedImage == nil {
                VStack(spacing: 16) {
                    Image(systemName: "photo.on.rectangle.angled")
                        .font(.system(size: 50, weight: .light))
                        .foregroundColor(Color.white.opacity(0.3))

                    Text("Select or capture an image")
                        .font(.system(size: 16, weight: .medium))
                        .foregroundColor(Color.white.opacity(0.4))
                }
            }

            if isProcessing {
                RoundedRectangle(cornerRadius: 20)
                    .fill(Color.black.opacity(0.7))

                VStack(spacing: 16) {
                    ProgressView()
                        .progressViewStyle(CircularProgressViewStyle(tint: .white))
                        .scaleEffect(1.5)

                    Text("Applying style transfer...")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundColor(.white)
                }
            }
        }
        .frame(maxWidth: .infinity)
        .frame(height: UIScreen.main.bounds.height * 0.45)
    }

    private var actionButtons: some View {
        VStack(spacing: 12) {
            HStack(spacing: 16) {
                Button(action: { showPhotoLibrary = true }) {
                    HStack(spacing: 10) {
                        Image(systemName: "photo.stack")
                            .font(.system(size: 18, weight: .semibold))
                        Text("Library")
                            .font(.system(size: 16, weight: .semibold))
                    }
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .frame(height: 54)
                    .background(
                        LinearGradient(
                            colors: [Color(hex: "667eea"), Color(hex: "764ba2")],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
                    .clipShape(RoundedRectangle(cornerRadius: 14))
                }

                Button(action: {
                    guard CameraPicker.isAvailable else {
                        errorMessage = "Camera is not available in the simulator. Use Library instead."
                        showError = true
                        return
                    }
                    showCamera = true
                }) {
                    HStack(spacing: 10) {
                        Image(systemName: "camera.fill")
                            .font(.system(size: 18, weight: .semibold))
                        Text("Camera")
                            .font(.system(size: 16, weight: .semibold))
                    }
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .frame(height: 54)
                    .background(
                        LinearGradient(
                            colors: [Color(hex: "f093fb"), Color(hex: "f5576c")],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
                    .clipShape(RoundedRectangle(cornerRadius: 14))
                }
                .disabled(!CameraPicker.isAvailable)
                .opacity(CameraPicker.isAvailable ? 1.0 : 0.5)
            }

            if selectedImage != nil {
                Button(action: {
                    applyStyleTransfer()
                }) {
                    HStack(spacing: 10) {
                        Image(systemName: "wand.and.rays")
                            .font(.system(size: 20, weight: .semibold))
                        Text(stylizedImage != nil ? "Re apply Style" : "Apply Style Transfer")
                            .font(.system(size: 17, weight: .bold))
                    }
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .frame(height: 58)
                    .background(
                        LinearGradient(
                            colors: [Color(hex: "e94560"), Color(hex: "ff6b6b")],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
                    .clipShape(RoundedRectangle(cornerRadius: 14))
                    .shadow(color: Color(hex: "e94560").opacity(0.4), radius: 12, x: 0, y: 6)
                }
                .disabled(isProcessing)
                .opacity(isProcessing ? 0.6 : 1.0)
                .transition(.move(edge: .bottom).combined(with: .opacity))
                .animation(.spring(response: 0.4, dampingFraction: 0.8), value: selectedImage != nil)
            }

            if stylizedImage != nil {
                Button(action: {
                    saveToGallery()
                }) {
                    HStack(spacing: 10) {
                        if isSaving {
                            ProgressView()
                                .progressViewStyle(CircularProgressViewStyle(tint: .white))
                                .scaleEffect(0.8)
                        } else {
                            Image(systemName: "square.and.arrow.down")
                                .font(.system(size: 18, weight: .semibold))
                        }
                        Text(isSaving ? "Saving..." : "Save to Gallery")
                            .font(.system(size: 16, weight: .semibold))
                    }
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
                    .shadow(color: Color(hex: "11998e").opacity(0.3), radius: 8, x: 0, y: 4)
                }
                .disabled(isSaving || isProcessing)
                .opacity((isSaving || isProcessing) ? 0.6 : 1.0)
                .transition(.move(edge: .bottom).combined(with: .opacity))
                .animation(.spring(response: 0.4, dampingFraction: 0.8), value: stylizedImage != nil)
            }
        }
    }

    private func applyStyleTransfer() {
        guard let inputImage = selectedImage else { return }

        isProcessing = true

        Task {
            do {
                let result = try await styleService.applyStyle(to: inputImage)
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
        guard let imageToSave = stylizedImage else { return }

        isSaving = true

        let imageSaver = ImageSaver()
        imageSaver.onSuccess = {
            DispatchQueue.main.async {
                self.isSaving = false
                self.showSaveSuccess = true
            }
        }
        imageSaver.onError = { error in
            DispatchQueue.main.async {
                self.isSaving = false
                self.errorMessage = error.localizedDescription
                self.showError = true
            }
        }
        imageSaver.saveImage(imageToSave)
    }

    private var statusIndicator: some View {
        HStack(spacing: 8) {
            Circle()
                .fill(modelLoaded ? Color.green : Color.orange)
                .frame(width: 8, height: 8)

            Text(modelLoaded ? "Model Ready" : "Loading model...")
                .font(.system(size: 12, weight: .medium))
                .foregroundColor(Color.white.opacity(0.5))
        }
        .padding(.bottom, 8)
    }

    private func verifyModel() {
        modelLoaded = styleService.isModelLoaded
        if modelLoaded {
            print("✅ Model loaded successfully")
        } else {
            print("❌ Model is not ready")
        }
    }
}

struct ResultFullScreenView: View {
    let originalImage: UIImage
    let stylizedImage: UIImage
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
        }
    }
}

struct BeforeAfterComparisonView: View {
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
                    .foregroundColor(Color(hex: "1a1a2e"))
                )
        }
        .accessibilityLabel("Before and after divider")
        .accessibilityHint("Drag left or right to compare the original and stylized image")
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

class ImageSaver: NSObject {
    var onSuccess: (() -> Void)?
    var onError: ((Error) -> Void)?

    func saveImage(_ image: UIImage) {
        UIImageWriteToSavedPhotosAlbum(image, self, #selector(saveCompleted), nil)
    }

    @objc func saveCompleted(_ image: UIImage, didFinishSavingWithError error: Error?, contextInfo: UnsafeRawPointer) {
        if let error = error {
            onError?(error)
        } else {
            onSuccess?()
        }
    }
}

#Preview {
    ContentView()
}

//
//  ContentView.swift
//  IPSTStyleApp
//
//  Created by EXPO on 12/4/25.
//

import SwiftUI
import CoreML
import Vision

struct ContentView: View {
    // MARK: - State
    @State private var selectedImage: UIImage?
    @State private var stylizedImage: UIImage?
    @State private var showPhotoLibrary = false
    @State private var showCamera = false
    @State private var modelLoaded = false
    @State private var isProcessing = false
    @State private var isSaving = false
    @State private var showStylized = false
    @State private var errorMessage: String?
    @State private var showError = false
    @State private var showSaveSuccess = false
    
    // MARK: - Services
    @StateObject private var styleService = StyleTransferService()
    
    var body: some View {
        NavigationView {
            ZStack {
                // Background gradient
                LinearGradient(
                    colors: [Color(hex: "1a1a2e"), Color(hex: "16213e")],
                    startPoint: .top,
                    endPoint: .bottom
                )
                .ignoresSafeArea()
                
                VStack(spacing: 24) {
                    // Header
                    headerView
                    
                    // Image Display Area
                    imageDisplayArea
                    
                    Spacer()
                    
                    // Action Buttons
                    actionButtons
                    
                    // Status indicator
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
        .onChange(of: selectedImage) { _ in
            // Reset stylized image when new image is selected
            stylizedImage = nil
            showStylized = false
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
    
    // MARK: - Header View
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
    
    // MARK: - Image Display Area
    private var imageDisplayArea: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 20)
                .fill(Color.white.opacity(0.05))
                .overlay(
                    RoundedRectangle(cornerRadius: 20)
                        .stroke(Color.white.opacity(0.1), lineWidth: 1)
                )
            
            // Determine which image to display
            if let displayImage = showStylized ? stylizedImage : selectedImage {
                Image(uiImage: displayImage)
                    .resizable()
                    .scaledToFit()
                    .clipShape(RoundedRectangle(cornerRadius: 16))
                    .padding(8)
                
                // Toggle button (only show if we have stylized result)
                if stylizedImage != nil {
                    VStack {
                        HStack {
                            Spacer()
                            Button(action: {
                                withAnimation(.easeInOut(duration: 0.2)) {
                                    showStylized.toggle()
                                }
                            }) {
                                HStack(spacing: 6) {
                                    Image(systemName: showStylized ? "photo" : "wand.and.stars")
                                        .font(.system(size: 12, weight: .semibold))
                                    Text(showStylized ? "Original" : "Stylized")
                                        .font(.system(size: 12, weight: .semibold))
                                }
                                .foregroundColor(.white)
                                .padding(.horizontal, 12)
                                .padding(.vertical, 8)
                                .background(Color.black.opacity(0.6))
                                .clipShape(Capsule())
                            }
                            .padding(16)
                        }
                        Spacer()
                    }
                }
            } else if selectedImage == nil {
                // Placeholder
                VStack(spacing: 16) {
                    Image(systemName: "photo.on.rectangle.angled")
                        .font(.system(size: 50, weight: .light))
                        .foregroundColor(Color.white.opacity(0.3))
                    
                    Text("Select or capture an image")
                        .font(.system(size: 16, weight: .medium))
                        .foregroundColor(Color.white.opacity(0.4))
                }
            }
            
            // Loading overlay
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
    
    // MARK: - Action Buttons
    private var actionButtons: some View {
        VStack(spacing: 12) {
            HStack(spacing: 16) {
                // Photo Library Button
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
                
                // Camera Button
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
            
            // Apply Style Button (shows when image is selected)
            if selectedImage != nil {
                Button(action: {
                    applyStyleTransfer()
                }) {
                    HStack(spacing: 10) {
                        Image(systemName: "wand.and.rays")
                            .font(.system(size: 20, weight: .semibold))
                        Text(stylizedImage != nil ? "Re-apply Style" : "Apply Style Transfer")
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
            
            // Save to Gallery Button (shows when stylized image is available)
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
    
    // MARK: - Style Transfer Action
    private func applyStyleTransfer() {
        guard let inputImage = selectedImage else { return }
        
        isProcessing = true
        
        Task {
            do {
                let result = try await styleService.applyStyle(to: inputImage)
                await MainActor.run {
                    stylizedImage = result
                    showStylized = true
                    isProcessing = false
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
    
    // MARK: - Save to Gallery Action
    private func saveToGallery() {
        guard let imageToSave = stylizedImage else { return }
        
        isSaving = true
        
        // Use ImageSaver helper class for callback handling
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
    
    // MARK: - Status Indicator
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
    
    // MARK: - Model Verification
    private func verifyModel() {
        do {
            let config = MLModelConfiguration()
            config.computeUnits = .all
            let _ = try ipst_style(configuration: config)
            modelLoaded = true
            print("✅ Model loaded successfully")
        } catch {
            modelLoaded = false
            print("❌ Error loading model: \(error)")
        }
    }
}

// MARK: - Color Extension for Hex Support
extension Color {
    init(hex: String) {
        let hex = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var int: UInt64 = 0
        Scanner(string: hex).scanHexInt64(&int)
        let a, r, g, b: UInt64
        switch hex.count {
        case 3: // RGB (12-bit)
            (a, r, g, b) = (255, (int >> 8) * 17, (int >> 4 & 0xF) * 17, (int & 0xF) * 17)
        case 6: // RGB (24-bit)
            (a, r, g, b) = (255, int >> 16, int >> 8 & 0xFF, int & 0xFF)
        case 8: // ARGB (32-bit)
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

// MARK: - Image Saver Helper
/// Helper class to handle UIImageWriteToSavedPhotosAlbum callback
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

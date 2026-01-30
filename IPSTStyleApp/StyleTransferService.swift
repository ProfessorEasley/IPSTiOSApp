//
//  StyleTransferService.swift
//  IPSTStyleApp
//
//  Created by EXPO on 12/11/25.
//

import Foundation
import CoreML
import UIKit
import CoreImage

/// Service class responsible for applying style transfer using the CoreML model
class StyleTransferService: ObservableObject {
    
    // MARK: - Properties
    
    private var model: ipst_style?
    @Published var isModelLoaded: Bool = false
    
    /// Model input size (from mlpackage specification)
    private let modelInputSize = CGSize(width: 480, height: 480)
    
    // MARK: - Initialization
    
    init() {
        loadModel()
    }
    
    /// Load the CoreML model
    private func loadModel() {
        do {
            let config = MLModelConfiguration()
            config.computeUnits = .all // Use CPU, GPU, and Neural Engine
            model = try ipst_style(configuration: config)
            isModelLoaded = true
            print("✅ StyleTransferService: Model loaded successfully")
        } catch {
            isModelLoaded = false
            print("❌ StyleTransferService: Failed to load model - \(error.localizedDescription)")
        }
    }
    
    // MARK: - Public Methods
    
    /// Apply style transfer to the given image
    /// - Parameter image: The input UIImage to stylize
    /// - Returns: The stylized UIImage
    /// - Throws: StyleTransferError if processing fails
    func applyStyle(to image: UIImage) async throws -> UIImage {
        guard let model = model else {
            throw StyleTransferError.modelNotLoaded
        }
        
        // Store original size to resize back later
        let originalSize = image.size
        
        // Step 1: Preprocess - Resize and convert to MLMultiArray
        guard let resizedImage = resizeImage(image, to: modelInputSize),
              let inputArray = createMLMultiArray(from: resizedImage) else {
            throw StyleTransferError.preprocessingFailed
        }
        
        // Step 2: Run inference
        let outputFeatures: MLFeatureProvider
        do {
            // Create input feature provider with the MLMultiArray
            let inputFeature = try MLDictionaryFeatureProvider(dictionary: [
                "input": MLFeatureValue(multiArray: inputArray)
            ])
            
            outputFeatures = try await Task.detached(priority: .userInitiated) {
                try model.model.prediction(from: inputFeature)
            }.value
        } catch {
            throw StyleTransferError.inferenceFailed(error.localizedDescription)
        }
        
        // Get the output MLMultiArray
        guard let outputValue = outputFeatures.featureValue(for: "var_21"),
              let outputMultiArray = outputValue.multiArrayValue else {
            throw StyleTransferError.postprocessingFailed
        }
        
        // Step 3: Postprocess - Convert MLMultiArray output to UIImage
        guard let outputImage = createImage(from: outputMultiArray, size: modelInputSize) else {
            throw StyleTransferError.postprocessingFailed
        }
        
        // Step 4: Resize back to original size (optional, for better quality display)
        guard let finalImage = resizeImage(outputImage, to: originalSize) else {
            return outputImage
        }
        
        return finalImage
    }
    
    // MARK: - Private Methods - Preprocessing
    
    /// Resize image to target size using letterboxing (maintains aspect ratio)
    private func resizeImage(_ image: UIImage, to targetSize: CGSize) -> UIImage? {
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1.0 // Use 1:1 pixel mapping
        
        let renderer = UIGraphicsImageRenderer(size: targetSize, format: format)
        
        return renderer.image { context in
            // Fill with black background (letterboxing)
            UIColor.black.setFill()
            context.fill(CGRect(origin: .zero, size: targetSize))
            
            // Calculate aspect-fit rect
            let aspectRatio = image.size.width / image.size.height
            let targetRatio = targetSize.width / targetSize.height
            
            var drawRect: CGRect
            
            if aspectRatio > targetRatio {
                // Image is wider - fit to width
                let height = targetSize.width / aspectRatio
                let y = (targetSize.height - height) / 2
                drawRect = CGRect(x: 0, y: y, width: targetSize.width, height: height)
            } else {
                // Image is taller - fit to height
                let width = targetSize.height * aspectRatio
                let x = (targetSize.width - width) / 2
                drawRect = CGRect(x: x, y: 0, width: width, height: targetSize.height)
            }
            
            image.draw(in: drawRect)
        }
    }
    
    /// Create an MLMultiArray from UIImage for CoreML input
    /// The model expects input in NCHW format: [1, 3, 480, 480] with Float32 values (0-255 range)
    private func createMLMultiArray(from image: UIImage) -> MLMultiArray? {
        guard let cgImage = image.cgImage else { return nil }
        
        let width = cgImage.width
        let height = cgImage.height
        
        // Create MLMultiArray with shape [1, 3, height, width]
        guard let multiArray = try? MLMultiArray(shape: [1, 3, NSNumber(value: height), NSNumber(value: width)], dataType: .float32) else {
            print("❌ Failed to create MLMultiArray")
            return nil
        }
        
        // Get pixel data from CGImage
        guard let pixelData = cgImage.dataProvider?.data,
              let data = CFDataGetBytePtr(pixelData) else {
            print("❌ Failed to get pixel data")
            return nil
        }
        
        let bytesPerPixel = cgImage.bitsPerPixel / 8
        let bytesPerRow = cgImage.bytesPerRow
        
        // Get pointer to MLMultiArray data
        let pointer = multiArray.dataPointer.bindMemory(to: Float32.self, capacity: multiArray.count)
        
        // Calculate stride for channel-first format
        let channelStride = height * width
        
        // Fill the MLMultiArray in NCHW format
        for y in 0..<height {
            for x in 0..<width {
                let pixelIndex = y * bytesPerRow + x * bytesPerPixel
                let arrayIndex = y * width + x
                
                // Extract RGB values (assuming RGBA or BGRA format)
                let r: Float32
                let g: Float32
                let b: Float32
                
                // Handle different pixel formats
                if cgImage.bitmapInfo.contains(.byteOrder32Little) {
                    // BGRA format (little endian)
                    b = Float32(data[pixelIndex])
                    g = Float32(data[pixelIndex + 1])
                    r = Float32(data[pixelIndex + 2])
                } else {
                    // RGBA format (big endian)
                    r = Float32(data[pixelIndex])
                    g = Float32(data[pixelIndex + 1])
                    b = Float32(data[pixelIndex + 2])
                }
                
                // Store in channel-first format [1, C, H, W]
                // Channel 0 (R)
                pointer[0 * channelStride + arrayIndex] = r
                // Channel 1 (G)
                pointer[1 * channelStride + arrayIndex] = g
                // Channel 2 (B)
                pointer[2 * channelStride + arrayIndex] = b
            }
        }
        
        return multiArray
    }
    
    // MARK: - Private Methods - Postprocessing
    
    /// Create UIImage from model output MLMultiArray
    /// The model output is expected to be in NCHW format: [1, 3, height, width]
    private func createImage(from multiArray: MLMultiArray, size: CGSize) -> UIImage? {
        let width = Int(size.width)
        let height = Int(size.height)
        
        // Verify the shape - expecting [1, 3, height, width] or [3, height, width]
        let shape = multiArray.shape.map { $0.intValue }
        
        let channels: Int
        let heightIndex: Int
        let widthIndex: Int
        
        if shape.count == 4 {
            // [1, 3, H, W] format
            channels = shape[1]
            heightIndex = 2
            widthIndex = 3
        } else if shape.count == 3 {
            // [3, H, W] format
            channels = shape[0]
            heightIndex = 1
            widthIndex = 2
        } else {
            print("❌ Unexpected MLMultiArray shape: \(shape)")
            return nil
        }
        
        guard channels == 3 else {
            print("❌ Expected 3 channels, got \(channels)")
            return nil
        }
        
        let outputHeight = shape[heightIndex]
        let outputWidth = shape[widthIndex]
        
        // Create pixel data buffer (RGBA format)
        var pixelData = [UInt8](repeating: 0, count: outputWidth * outputHeight * 4)
        
        // Get pointer to MLMultiArray data
        let pointer = multiArray.dataPointer.bindMemory(to: Float32.self, capacity: multiArray.count)
        
        // Calculate strides for accessing the data
        let channelStride = outputHeight * outputWidth
        
        for y in 0..<outputHeight {
            for x in 0..<outputWidth {
                let pixelIndex = y * outputWidth + x
                let rgbaIndex = pixelIndex * 4
                
                // Extract RGB values (model output is typically in range 0-255 or 0-1)
                var r = pointer[0 * channelStride + pixelIndex]
                var g = pointer[1 * channelStride + pixelIndex]
                var b = pointer[2 * channelStride + pixelIndex]
                
                // Clamp values to 0-255 range
                // If values are in 0-1 range, scale them up
                if r <= 1.0 && g <= 1.0 && b <= 1.0 && r >= 0 && g >= 0 && b >= 0 {
                    r *= 255.0
                    g *= 255.0
                    b *= 255.0
                }
                
                // Clamp to valid range
                r = max(0, min(255, r))
                g = max(0, min(255, g))
                b = max(0, min(255, b))
                
                pixelData[rgbaIndex] = UInt8(r)
                pixelData[rgbaIndex + 1] = UInt8(g)
                pixelData[rgbaIndex + 2] = UInt8(b)
                pixelData[rgbaIndex + 3] = 255 // Alpha
            }
        }
        
        // Create CGImage from pixel data
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        let bitmapInfo = CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue)
        
        guard let provider = CGDataProvider(data: Data(pixelData) as CFData),
              let cgImage = CGImage(
                width: outputWidth,
                height: outputHeight,
                bitsPerComponent: 8,
                bitsPerPixel: 32,
                bytesPerRow: outputWidth * 4,
                space: colorSpace,
                bitmapInfo: bitmapInfo,
                provider: provider,
                decode: nil,
                shouldInterpolate: true,
                intent: .defaultIntent
              ) else {
            return nil
        }
        
        return UIImage(cgImage: cgImage)
    }
}

// MARK: - Error Types

enum StyleTransferError: LocalizedError {
    case modelNotLoaded
    case preprocessingFailed
    case inferenceFailed(String)
    case postprocessingFailed
    
    var errorDescription: String? {
        switch self {
        case .modelNotLoaded:
            return "Style transfer model is not loaded"
        case .preprocessingFailed:
            return "Failed to preprocess the image"
        case .inferenceFailed(let reason):
            return "Model inference failed: \(reason)"
        case .postprocessingFailed:
            return "Failed to create output image"
        }
    }
}


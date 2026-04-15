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
            config.computeUnits = .all
            
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
    func applyStyle(to image: UIImage) async throws -> UIImage {
        guard let model = model else {
            throw StyleTransferError.modelNotLoaded
        }
        
        let originalSize = image.size
        
        guard let resizedImage = resizeImage(image, to: modelInputSize),
              let inputArray = createNormalizedMLMultiArray(from: resizedImage) else {
            throw StyleTransferError.preprocessingFailed
        }
        
        let outputFeatures: MLFeatureProvider
        
        do {
            let inputFeature = try MLDictionaryFeatureProvider(dictionary: [
                "input": MLFeatureValue(multiArray: inputArray)
            ])
            
            outputFeatures = try await Task.detached(priority: .userInitiated) {
                try model.model.prediction(from: inputFeature)
            }.value
        } catch {
            throw StyleTransferError.inferenceFailed(error.localizedDescription)
        }
        
        guard let outputValue = outputFeatures.featureValue(for: "var_21"),
              let deltaArray = outputValue.multiArrayValue else {
            throw StyleTransferError.postprocessingFailed
        }
        
        guard let stylizedImage = createStyledImage(
            from: inputArray,
            delta: deltaArray,
            size: modelInputSize
        ) else {
            throw StyleTransferError.postprocessingFailed
        }
        
        guard let finalImage = resizeImage(stylizedImage, to: originalSize) else {
            return stylizedImage
        }
        
        return finalImage
    }
    
    // MARK: - Preprocessing
    private func resizeImage(_ image: UIImage, to targetSize: CGSize) -> UIImage? {
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1.0
        
        let renderer = UIGraphicsImageRenderer(size: targetSize, format: format)
        
        return renderer.image { context in
            UIColor.black.setFill()
            context.fill(CGRect(origin: .zero, size: targetSize))
            
            let aspectRatio = image.size.width / image.size.height
            let targetRatio = targetSize.width / targetSize.height
            
            var drawRect: CGRect
            
            if aspectRatio > targetRatio {
                let height = targetSize.width / aspectRatio
                let y = (targetSize.height - height) / 2
                drawRect = CGRect(x: 0, y: y, width: targetSize.width, height: height)
            } else {
                let width = targetSize.height * aspectRatio
                let x = (targetSize.width - width) / 2
                drawRect = CGRect(x: x, y: 0, width: width, height: targetSize.height)
            }
            
            image.draw(in: drawRect)
        }
    }
    
    private func createNormalizedMLMultiArray(from image: UIImage) -> MLMultiArray? {
        guard let cgImage = image.cgImage else { return nil }
        
        let width = cgImage.width
        let height = cgImage.height
        
        guard let multiArray = try? MLMultiArray(
            shape: [1, 3, NSNumber(value: height), NSNumber(value: width)],
            dataType: .float32
        ) else {
            return nil
        }
        
        guard let pixelData = cgImage.dataProvider?.data,
              let data = CFDataGetBytePtr(pixelData) else {
            return nil
        }
        
        let bytesPerPixel = cgImage.bitsPerPixel / 8
        let bytesPerRow = cgImage.bytesPerRow
        
        let pointer = multiArray.dataPointer.bindMemory(to: Float32.self, capacity: multiArray.count)
        let channelStride = height * width
        
        let mean: [Float32] = [0.485, 0.456, 0.406]
        let std: [Float32] = [0.229, 0.224, 0.225]
        
        for y in 0..<height {
            for x in 0..<width {
                let pixelIndex = y * bytesPerRow + x * bytesPerPixel
                let arrayIndex = y * width + x
                
                let r = Float32(data[pixelIndex + 2]) / 255.0
                let g = Float32(data[pixelIndex + 1]) / 255.0
                let b = Float32(data[pixelIndex]) / 255.0
                
                pointer[0 * channelStride + arrayIndex] = (r - mean[0]) / std[0]
                pointer[1 * channelStride + arrayIndex] = (g - mean[1]) / std[1]
                pointer[2 * channelStride + arrayIndex] = (b - mean[2]) / std[2]
            }
        }
        
        return multiArray
    }
    
    private func createStyledImage(
        from input: MLMultiArray,
        delta: MLMultiArray,
        size: CGSize
    ) -> UIImage? {
        let shape = input.shape.map { $0.intValue }
        guard shape.count == 4 else { return nil }
        
        let height = shape[2]
        let width = shape[3]
        let channelStride = height * width
        
        let inputPtr = input.dataPointer.bindMemory(to: Float32.self, capacity: input.count)
        let deltaPtr = delta.dataPointer.bindMemory(to: Float32.self, capacity: delta.count)
        
        let mean: [Float32] = [0.485, 0.456, 0.406]
        let std: [Float32] = [0.229, 0.224, 0.225]
        
        var pixelData = [UInt8](repeating: 0, count: width * height * 4)
        
        for y in 0..<height {
            for x in 0..<width {
                let pixelIndex = y * width + x
                let rgbaIndex = pixelIndex * 4
                
                let rNorm = inputPtr[0 * channelStride + pixelIndex] + deltaPtr[0 * channelStride + pixelIndex]
                let gNorm = inputPtr[1 * channelStride + pixelIndex] + deltaPtr[1 * channelStride + pixelIndex]
                let bNorm = inputPtr[2 * channelStride + pixelIndex] + deltaPtr[2 * channelStride + pixelIndex]
                
                var r = (rNorm * std[0] + mean[0]) * 255.0
                var g = (gNorm * std[1] + mean[1]) * 255.0
                var b = (bNorm * std[2] + mean[2]) * 255.0
                
                r = max(0, min(255, r))
                g = max(0, min(255, g))
                b = max(0, min(255, b))
                
                pixelData[rgbaIndex] = UInt8(r)
                pixelData[rgbaIndex + 1] = UInt8(g)
                pixelData[rgbaIndex + 2] = UInt8(b)
                pixelData[rgbaIndex + 3] = 255
            }
        }
        
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        let bitmapInfo = CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue)
        
        guard let provider = CGDataProvider(data: Data(pixelData) as CFData),
              let cgImage = CGImage(
                width: width,
                height: height,
                bitsPerComponent: 8,
                bitsPerPixel: 32,
                bytesPerRow: width * 4,
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

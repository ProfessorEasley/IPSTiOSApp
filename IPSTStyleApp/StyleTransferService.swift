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

class StyleTransferService: ObservableObject {

    private var model: ipst_style?
    @Published var isModelLoaded: Bool = false

    private let modelInputSize = CGSize(width: 480, height: 480)

    init() {
        loadModel()
    }

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
    private func createImageDirect(from output: MLMultiArray) -> UIImage? {
        let shape = output.shape.map { $0.intValue }
        guard shape.count == 4 else { return nil }

        let height = shape[2]
        let width = shape[3]
        let channelStride = height * width

        let ptr = output.dataPointer.bindMemory(to: Float32.self, capacity: output.count)

        let mean: [Float32] = [0.485, 0.456, 0.406]
        let std: [Float32] = [0.229, 0.224, 0.225]

        var pixelData = [UInt8](repeating: 0, count: width * height * 4)

        for y in 0..<height {
            for x in 0..<width {
                let pixelIndex = y * width + x
                let rgbaIndex = pixelIndex * 4

                // 🔥 correct channel order
                let bNorm = ptr[0 * channelStride + pixelIndex]
                let gNorm = ptr[1 * channelStride + pixelIndex]
                let rNorm = ptr[2 * channelStride + pixelIndex]

                // 🔥 denormalize
                var r = rNorm * std[0] + mean[0]
                var g = gNorm * std[1] + mean[1]
                var b = bNorm * std[2] + mean[2]

                // 🔥 clamp to [0,1]
                r = max(0, min(1, r))
                g = max(0, min(1, g))
                b = max(0, min(1, b))

                pixelData[rgbaIndex]     = UInt8(r * 255.0)
                pixelData[rgbaIndex + 1] = UInt8(g * 255.0)
                pixelData[rgbaIndex + 2] = UInt8(b * 255.0)
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
    func applyStyle(to image: UIImage) async throws -> UIImage {
        guard let model = model else {
            throw StyleTransferError.modelNotLoaded
        }

        let originalSize = image.size
        print("\n=== IPST iOS StyleTransferService Debug ===")
        print("Original image size: \(originalSize)")

        guard let resizedImage = resizeImage(image, to: modelInputSize),
              let inputArray = createNormalizedMLMultiArray(from: resizedImage) else {
            throw StyleTransferError.preprocessingFailed
        }

        let inputPtr = inputArray.dataPointer.bindMemory(to: Float32.self, capacity: inputArray.count)
        let inputValues = (0..<inputArray.count).map { inputPtr[$0] }
        let inputMin = inputValues.min() ?? 0
        let inputMax = inputValues.max() ?? 0
        let inputMean = Float(inputValues.reduce(0, +)) / Float(inputValues.count)

        print("✓ Input MLMultiArray shape: \(inputArray.shape)")
        print("  Normalized range: [\(String(format: "%.4f", inputMin)), \(String(format: "%.4f", inputMax))]")
        print("  Mean value: \(String(format: "%.4f", inputMean))")

        let output: ipst_styleOutput
        do {
            output = try await Task.detached(priority: .userInitiated) {
                try model.prediction(input: inputArray)
            }.value
        } catch {
            throw StyleTransferError.inferenceFailed(error.localizedDescription)
        }

        let outputArray = output.var_22

        let outPtr = outputArray.dataPointer.bindMemory(to: Float32.self, capacity: outputArray.count)
        let outputValues = (0..<outputArray.count).map { outPtr[$0] }
        let outputMin = outputValues.min() ?? 0
        let outputMax = outputValues.max() ?? 0
        let outputMean = Float(outputValues.reduce(0, +)) / Float(outputValues.count)

        print("✓ Delta/Output array shape: \(outputArray.shape)")
        print("  Delta range: [\(String(format: "%.4f", outputMin)), \(String(format: "%.4f", outputMax))]")
        print("  Mean delta: \(String(format: "%.4f", outputMean))")

        guard let stylizedImage = createFinalImage(input: inputArray, output: outputArray) else {
            throw StyleTransferError.postprocessingFailed
        }

        if let finalImage = resizeImage(stylizedImage, to: originalSize) {
            return applyColorCorrection(finalImage)
        }

        return applyColorCorrection(stylizedImage)
    }

    func applyStyle(source: UIImage, target: UIImage) async throws -> UIImage {
        _ = source
        return try await applyStyle(to: target)
    }

    func applyColorCorrection(_ image: UIImage) -> UIImage {
        guard let ciImage = CIImage(image: image) else { return image }

        let filter = CIFilter(name: "CIColorMatrix")!
        filter.setValue(ciImage, forKey: kCIInputImageKey)

        // 🔥 reduce green + boost red slightly → shifts orange → pink
        filter.setValue(CIVector(x: 1.1, y: 0, z: 0, w: 0), forKey: "inputRVector")
        filter.setValue(CIVector(x: 0, y: 0.9, z: 0, w: 0), forKey: "inputGVector")
        filter.setValue(CIVector(x: 0, y: 0, z: 1.0, w: 0), forKey: "inputBVector")

        let context = CIContext()
        guard let outputImage = filter.outputImage,
              let cgImage = context.createCGImage(outputImage, from: outputImage.extent) else {
            return image
        }

        return UIImage(cgImage: cgImage)
    }
    private func createFinalImage(input: MLMultiArray, output: MLMultiArray) -> UIImage? {
        let shape = output.shape.map { $0.intValue }
        guard shape.count == 4 else { return nil }

        let height = shape[2]
        let width = shape[3]
        let stride = height * width

        let inPtr = input.dataPointer.bindMemory(to: Float32.self, capacity: input.count)
        let outPtr = output.dataPointer.bindMemory(to: Float32.self, capacity: output.count)

        let mean: [Float32] = [0.485, 0.456, 0.406]
        let std: [Float32] = [0.229, 0.224, 0.225]

        var pixelData = [UInt8](repeating: 0, count: width * height * 4)

        let alpha: Float32 = 0.6   // 🔥 tune this (0.5–0.7)

        for y in 0..<height {
            for x in 0..<width {
                let idx = y * width + x
                let rgba = idx * 4

                // channel mapping (correct)
                let bOut = outPtr[0 * stride + idx]
                let gOut = outPtr[1 * stride + idx]
                let rOut = outPtr[2 * stride + idx]

                let bIn = inPtr[0 * stride + idx]
                let gIn = inPtr[1 * stride + idx]
                let rIn = inPtr[2 * stride + idx]

                // 🔥 denormalize BOTH first
                let rOutImg = rOut * std[0] + mean[0]
                let gOutImg = gOut * std[1] + mean[1]
                let bOutImg = bOut * std[2] + mean[2]

                let rInImg = rIn * std[0] + mean[0]
                let gInImg = gIn * std[1] + mean[1]
                let bInImg = bIn * std[2] + mean[2]

                // 🔥 blend in image space (correct)
                var r = alpha * rOutImg + (1 - alpha) * rInImg
                var g = alpha * gOutImg + (1 - alpha) * gInImg
                var b = alpha * bOutImg + (1 - alpha) * bInImg

                r = max(0, min(1, r))
                g = max(0, min(1, g))
                b = max(0, min(1, b))

                pixelData[rgba]     = UInt8(r * 255)
                pixelData[rgba + 1] = UInt8(g * 255)
                pixelData[rgba + 2] = UInt8(b * 255)
                pixelData[rgba + 3] = 255
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
    private func resizeImage(_ image: UIImage, to targetSize: CGSize) -> UIImage? {
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1.0

        let renderer = UIGraphicsImageRenderer(size: targetSize, format: format)
        return renderer.image { _ in
            image.draw(in: CGRect(origin: .zero, size: targetSize))
        }
    }

    private func createNormalizedMLMultiArray(from image: UIImage) -> MLMultiArray? {
        let width = Int(modelInputSize.width)
        let height = Int(modelInputSize.height)

        guard let cgImage = image.cgImage else { return nil }

        let colorSpace = CGColorSpaceCreateDeviceRGB()
        let bytesPerPixel = 4
        let bytesPerRow = bytesPerPixel * width
        var rawBytes = [UInt8](repeating: 0, count: height * bytesPerRow)

        let renderOK = rawBytes.withUnsafeMutableBytes { rawBuffer -> Bool in
            guard let baseAddress = rawBuffer.baseAddress else { return false }

            guard let context = CGContext(
                data: baseAddress,
                width: width,
                height: height,
                bitsPerComponent: 8,
                bytesPerRow: bytesPerRow,
                space: colorSpace,
                bitmapInfo: CGBitmapInfo(
                    rawValue: CGImageAlphaInfo.premultipliedLast.rawValue |
                    CGBitmapInfo.byteOrder32Big.rawValue
                ).rawValue
            ) else {
                return false
            }

            context.interpolationQuality = .high
            context.draw(cgImage, in: CGRect(x: 0, y: 0, width: width, height: height))
            return true
        }

        guard renderOK else {
            print("Failed to render image into RGBA buffer")
            return nil
        }

        guard let multiArray = try? MLMultiArray(
            shape: [1, 3, NSNumber(value: height), NSNumber(value: width)],
            dataType: .float32
        ) else {
            print("Failed to create MLMultiArray")
            return nil
        }

        let pointer = multiArray.dataPointer.bindMemory(to: Float32.self, capacity: multiArray.count)
        let channelStride = height * width

        let mean: [Float32] = [0.485, 0.456, 0.406]
        let std: [Float32] = [0.229, 0.224, 0.225]

        for y in 0..<height {
            for x in 0..<width {
                let pixelIndex = y * bytesPerRow + x * bytesPerPixel
                let arrayIndex = y * width + x

                let r = Float32(rawBytes[pixelIndex]) / 255.0
                let g = Float32(rawBytes[pixelIndex + 1]) / 255.0
                let b = Float32(rawBytes[pixelIndex + 2]) / 255.0

                pointer[0 * channelStride + arrayIndex] = (r - mean[0]) / std[0]
                pointer[1 * channelStride + arrayIndex] = (g - mean[1]) / std[1]
                pointer[2 * channelStride + arrayIndex] = (b - mean[2]) / std[2]
            }
        }

        return multiArray
    }

    private func createStyledImage(from input: MLMultiArray, output: MLMultiArray, isDebugMode: Bool = false) -> UIImage? {
        let direct = renderCandidateImage(input: input, output: output, useResidual: false, isDebugMode: isDebugMode)
        let residual = renderCandidateImage(input: input, output: output, useResidual: true, isDebugMode: isDebugMode)

        if let directResult = direct, let residualResult = residual {
            let selectedUseResidual = directResult.1 <= residualResult.1
            if isDebugMode {
                print("\n🔄 Comparing direct vs residual:")
                print("  Direct clipped pixels: \(directResult.1)")
                print("  Residual clipped pixels: \(residualResult.1)")
                print("  Selected: \(selectedUseResidual ? "RESIDUAL" : "DIRECT")")
            }
            return selectedUseResidual ? residualResult.0 : directResult.0
        } else if let directResult = direct {
            if isDebugMode { print("  Using: DIRECT (residual failed)") }
            return directResult.0
        } else if let residualResult = residual {
            if isDebugMode { print("  Using: RESIDUAL (direct failed)") }
            return residualResult.0
        } else {
            return nil
        }
    }

    private func renderCandidateImage(
        input: MLMultiArray,
        output: MLMultiArray,
        useResidual: Bool,
        isDebugMode: Bool = false
    ) -> (UIImage, Int)? {
        let inputShape = input.shape.map { $0.intValue }
        let outputShape = output.shape.map { $0.intValue }

        guard inputShape.count == 4 else { return nil }

        let inputHeight = inputShape[2]
        let inputWidth = inputShape[3]
        let inputStride = inputHeight * inputWidth

        let outputHeight: Int
        let outputWidth: Int
        let outputStride: Int

        if outputShape.count == 4 {
            outputHeight = outputShape[2]
            outputWidth = outputShape[3]
            outputStride = outputHeight * outputWidth
        } else if outputShape.count == 3 {
            outputHeight = outputShape[1]
            outputWidth = outputShape[2]
            outputStride = outputHeight * outputWidth
        } else {
            return nil
        }

        let inputPtr = input.dataPointer.bindMemory(to: Float32.self, capacity: input.count)
        let outputPtr = output.dataPointer.bindMemory(to: Float32.self, capacity: output.count)

        let mean: [Float32] = [0.485, 0.456, 0.406]
        let std: [Float32] = [0.229, 0.224, 0.225]

        var pixelData = [UInt8](repeating: 0, count: outputWidth * outputHeight * 4)
        var clippedCount = 0

        for y in 0..<outputHeight {
            for x in 0..<outputWidth {
                let pixelIndex = y * outputWidth + x
                let rgbaIndex = pixelIndex * 4

                let rNorm: Float32
                let gNorm: Float32
                let bNorm: Float32

                if useResidual {
                    let inIndex = min(pixelIndex, inputStride - 1)
                    let outIndex = min(pixelIndex, outputStride - 1)

                    rNorm = inputPtr[0 * inputStride + inIndex] + outputPtr[0 * outputStride + outIndex]
                    gNorm = inputPtr[1 * inputStride + inIndex] + outputPtr[1 * outputStride + outIndex]
                    bNorm = inputPtr[2 * inputStride + inIndex] + outputPtr[2 * outputStride + outIndex]
                } else {
                    let outIndex = min(pixelIndex, outputStride - 1)
                    rNorm = outputPtr[0 * outputStride + outIndex]
                    gNorm = outputPtr[1 * outputStride + outIndex]
                    bNorm = outputPtr[2 * outputStride + outIndex]
                }

                var r = (rNorm * std[0] + mean[0]) * 255.0
                var g = (gNorm * std[1] + mean[1]) * 255.0
                var b = (bNorm * std[2] + mean[2]) * 255.0

                if r < 0 || r > 255 { clippedCount += 1 }
                if g < 0 || g > 255 { clippedCount += 1 }
                if b < 0 || b > 255 { clippedCount += 1 }

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

        return (UIImage(cgImage: cgImage), clippedCount)
    }
}

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

import CoreML
import Foundation

nonisolated enum FunASRNanoANEPreparation {
    static func compile(_ package: URL) async throws -> URL {
        try Task.checkCancellation()
        let task = Task.detached(priority: .utility) {
            // Validate the package's internal references before asking Core ML to read it.
            let data = try Data(contentsOf: package.appendingPathComponent("Manifest.json"))
            guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                let entries = json["itemInfoEntries"] as? [String: [String: Any]], !entries.isEmpty,
                entries.values.allSatisfy({ entry in
                    guard let path = entry["path"] as? String else { return false }
                    return FunASRNanoANEManifest.isSafePath(path)
                })
            else { throw ANEModelInstallError.invalidPackage }
            try Task.checkCancellation()
            let compiled = try MLModel.compileModel(at: package)
            do { try Task.checkCancellation(); return compiled } catch {
                try? FileManager.default.removeItem(at: compiled); throw error
            }
        }
        return try await withTaskCancellationHandler {
            try await task.value
        } onCancel: {
            task.cancel()
        }
    }

    static func prepare(_ compiled: URL, progress: @escaping @Sendable (ANEInstallationProgress) -> Void) async throws {
        guard #available(macOS 15, *), ANEModelReadiness.supported else { throw ANEModelInstallError.unsupported }
        try Task.checkCancellation()
        let task = Task.detached(priority: .utility) {
            try Task.checkCancellation()
            let configuration = MLModelConfiguration()
            configuration.computeUnits = .cpuAndNeuralEngine
            progress(.preparing(0, 4))
            let model = try MLModel(contentsOf: compiled, configuration: configuration)
            let metadata = model.modelDescription.metadata[.creatorDefinedKey] as? [String: String]
            guard metadata?["stet.encoder.contract"] == FunASRNanoANEManifest.modelContract,
                model.modelDescription.inputDescriptionsByName.keys.sorted()
                    == ["attention_bias", "positioned_features", "valid_mask"]
            else { throw ANEModelInstallError.invalidModel }
            for (index, frames) in [64, 128, 256, 512].enumerated() {
                try Task.checkCancellation()
                progress(.preparing(index, 4))
                try autoreleasepool {
                    let features = try MLMultiArray(shape: [1, 560, 1, NSNumber(value: frames)], dataType: .float32)
                    let mask = try MLMultiArray(shape: [1, 1, 1, NSNumber(value: frames)], dataType: .float32)
                    let bias = try MLMultiArray(shape: [1, NSNumber(value: frames), 1, 1], dataType: .float32)
                    let input = features.dataPointer.assumingMemoryBound(to: Float.self)
                    let valid = mask.dataPointer.assumingMemoryBound(to: Float.self)
                    let attention = bias.dataPointer.assumingMemoryBound(to: Float.self)
                    let silence = log(Float.ulpOfOne) * sqrt(Float(512))
                    for t in 0..<frames { valid[t] = 1; attention[t] = 0 }
                    for d in 0..<280 {
                        let frequency = exp(-Double(d) * log(10000.0) / 279.0)
                        for t in 0..<frames {
                            input[d * frames + t] = silence + Float(sin(Double(t + 1) * frequency))
                            input[(d + 280) * frames + t] = silence + Float(cos(Double(t + 1) * frequency))
                        }
                    }
                    let provider = try MLDictionaryFeatureProvider(dictionary: [
                        "positioned_features": features, "valid_mask": mask, "attention_bias": bias,
                    ])
                    let result = try model.prediction(from: provider)
                    guard let output = result.featureValue(for: "audio_embeds")?.multiArrayValue,
                        output.dataType == .float32, output.shape.map(\.intValue) == [1, 1024, 1, frames]
                    else { throw ANEModelInstallError.invalidModel }
                    let values = output.dataPointer.assumingMemoryBound(to: Float.self)
                    for channel in 0..<1024 {
                        for time in 0..<frames {
                            guard
                                values[channel * output.strides[1].intValue + time * output.strides[3].intValue]
                                    .isFinite
                            else { throw ANEModelInstallError.invalidModel }
                        }
                    }
                }
                progress(.preparing(index + 1, 4))
            }
            let plan = try await MLComputePlan.load(contentsOf: compiled, configuration: configuration)
            guard case .program(let program) = plan.modelStructure else { throw ANEModelInstallError.invalidModel }
            var aneCount = 0
            var cpuCount = 0
            var aneCost = 0.0
            var totalCost = 0.0
            func inspect(_ block: MLModelStructure.Program.Block) {
                for operation in block.operations {
                    if let usage = plan.deviceUsage(for: operation) {
                        let cost = plan.estimatedCost(of: operation)?.weight ?? 0
                        totalCost += cost
                        if case .neuralEngine = usage.preferred {
                            aneCount += 1; aneCost += cost
                        } else {
                            cpuCount += 1
                        }
                    }
                    for child in operation.blocks { inspect(child) }
                }
            }
            for function in program.functions.values { inspect(function.block) }
            guard aneCount > 0, totalCost > 0 ? aneCost / totalCost >= 0.95 : cpuCount == 0 else {
                throw ANEModelInstallError.noANE
            }
            try Task.checkCancellation()
        }
        try await withTaskCancellationHandler {
            try await task.value
        } onCancel: {
            task.cancel()
        }
    }
}

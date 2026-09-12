#import <CoreML/CoreML.h>
#import <Foundation/Foundation.h>

#include "stet_funasr_coreml.hpp"

#include <cstdint>
#include <cstring>
#include <string>

namespace {

constexpr int kFeatureDim = 560;
constexpr int kBuckets[] = {128, 256, 512, 1024, 1800};
constexpr int kBucketCount = sizeof(kBuckets) / sizeof(kBuckets[0]);

std::string ns_error(NSError *error) {
    if (error == nil || error.localizedDescription == nil) {
        return "unknown CoreML error";
    }
    return std::string(error.localizedDescription.UTF8String);
}

int bucket_for(int frames) {
    for (int index = 0; index < kBucketCount; ++index) {
        if (frames <= kBuckets[index]) {
            return kBuckets[index];
        }
    }
    return -1;
}

bool copy_valid_frames(MLMultiArray *embeds, int frames, std::vector<float> &out, int &embed_dim, std::string &error) {
    if (embeds == nil || embeds.shape.count < 3) {
        error = "encoder output is missing";
        return false;
    }
    const int out_frames = embeds.shape[1].intValue;
    embed_dim = embeds.shape[2].intValue;
    if (frames > out_frames || embed_dim <= 0) {
        error = "encoder output shape does not cover the valid frames";
        return false;
    }
    const NSInteger stride1 = embeds.strides[1].integerValue;
    const NSInteger stride2 = embeds.strides[2].integerValue;
    const float *src = static_cast<const float *>(embeds.dataPointer);
    out.assign(static_cast<size_t>(frames) * static_cast<size_t>(embed_dim), 0.0f);
    if (stride2 == 1 && stride1 == embed_dim) {
        std::memcpy(out.data(), src, out.size() * sizeof(float));
        return true;
    }
    for (int time = 0; time < frames; ++time) {
        for (int dim = 0; dim < embed_dim; ++dim) {
            out[static_cast<size_t>(time) * static_cast<size_t>(embed_dim) + static_cast<size_t>(dim)] =
                src[time * stride1 + dim * stride2];
        }
    }
    return true;
}

}  // namespace

struct StetCoreMLEncoder::Impl {
    MLModel *model = nil;
};

StetCoreMLEncoder::StetCoreMLEncoder() : impl(std::make_unique<Impl>()) {}
StetCoreMLEncoder::~StetCoreMLEncoder() = default;

bool stet_coreml_is_model_path(const char *path) {
    if (path == nullptr || path[0] == '\0') {
        return false;
    }
    std::string value(path);
    while (!value.empty() && (value.back() == '/' || value.back() == '\\')) {
        value.pop_back();
    }
    auto ends_with = [&](const char *suffix) {
        const size_t length = std::strlen(suffix);
        return value.size() >= length && value.compare(value.size() - length, length, suffix) == 0;
    };
    return ends_with(".mlmodelc") || ends_with(".mlpackage") || ends_with(".mlmodel");
}

bool StetCoreMLEncoder::load(const char *path, std::string &error) {
    @autoreleasepool {
        if (path == nullptr) {
            error = "CoreML encoder path is required";
            return false;
        }
        NSURL *url = [NSURL fileURLWithPath:[NSString stringWithUTF8String:path] isDirectory:YES];
        NSFileManager *files = NSFileManager.defaultManager;
        BOOL is_directory = NO;
        if (![files fileExistsAtPath:url.path isDirectory:&is_directory]) {
            error = "CoreML encoder is missing";
            return false;
        }
        MLModelConfiguration *config = [[MLModelConfiguration alloc] init];
        // Dynamic attention masks fail ANECCompile. CPU_AND_NE / All then spend ~20s
        // trying ANE on every process start. CPU-only stays finite and loads in ~2s.
        config.computeUnits = MLComputeUnitsCPUOnly;
        NSError *load_error = nil;
        MLModel *model = [MLModel modelWithContentsOfURL:url configuration:config error:&load_error];
        if (model == nil) {
            error = "CoreML encoder could not be loaded: " + ns_error(load_error);
            return false;
        }
        impl->model = model;
        return true;
    }
}

bool StetCoreMLEncoder::encode(
    const float *fbank,
    int frames,
    int feature_dim,
    std::vector<float> &out,
    int &embed_dim,
    std::string &error
) {
    @autoreleasepool {
        if (impl->model == nil) {
            error = "CoreML encoder is not loaded";
            return false;
        }
        if (fbank == nullptr || frames <= 0 || feature_dim != kFeatureDim) {
            error = "CoreML encoder input is invalid";
            return false;
        }
        const int bucket = bucket_for(frames);
        if (bucket < 0) {
            error = "audio is longer than the CoreML encoder sequence buckets";
            return false;
        }

        NSError *array_error = nil;
        MLMultiArray *speech = [[MLMultiArray alloc]
            initWithShape:@[ @1, @(bucket), @(kFeatureDim) ]
            dataType:MLMultiArrayDataTypeFloat32
            error:&array_error];
        if (speech == nil) {
            error = "unable to allocate encoder speech array: " + ns_error(array_error);
            return false;
        }
        float *speech_ptr = static_cast<float *>(speech.dataPointer);
        const NSInteger speech_stride1 = speech.strides[1].integerValue;
        const NSInteger speech_stride2 = speech.strides[2].integerValue;
        const size_t bucket_floats = static_cast<size_t>(bucket) * static_cast<size_t>(kFeatureDim);
        std::memset(speech_ptr, 0, bucket_floats * sizeof(float));
        if (speech_stride2 == 1 && speech_stride1 == kFeatureDim) {
            std::memcpy(
                speech_ptr,
                fbank,
                static_cast<size_t>(frames) * static_cast<size_t>(kFeatureDim) * sizeof(float)
            );
        } else {
            for (int time = 0; time < frames; ++time) {
                for (int dim = 0; dim < kFeatureDim; ++dim) {
                    speech_ptr[time * speech_stride1 + dim * speech_stride2] =
                        fbank[time * kFeatureDim + dim];
                }
            }
        }

        MLMultiArray *lengths = [[MLMultiArray alloc]
            initWithShape:@[ @1 ]
            dataType:MLMultiArrayDataTypeInt32
            error:&array_error];
        if (lengths == nil) {
            error = "unable to allocate encoder length array: " + ns_error(array_error);
            return false;
        }
        *static_cast<int32_t *>(lengths.dataPointer) = frames;

        NSError *provider_error = nil;
        MLDictionaryFeatureProvider *input = [[MLDictionaryFeatureProvider alloc]
            initWithDictionary:@{
                @"speech": [MLFeatureValue featureValueWithMultiArray:speech],
                @"speech_lengths": [MLFeatureValue featureValueWithMultiArray:lengths],
            }
            error:&provider_error];
        if (input == nil) {
            error = "unable to build encoder input: " + ns_error(provider_error);
            return false;
        }

        NSError *predict_error = nil;
        id<MLFeatureProvider> prediction = [impl->model predictionFromFeatures:input error:&predict_error];
        if (prediction == nil) {
            error = "CoreML encoder inference failed: " + ns_error(predict_error);
            return false;
        }
        MLFeatureValue *value = [prediction featureValueForName:@"audio_embeds"];
        if (value == nil) {
            NSSet<NSString *> *names = prediction.featureNames;
            if (names.count == 1) {
                value = [prediction featureValueForName:names.anyObject];
            }
        }
        if (value == nil || value.multiArrayValue == nil) {
            error = "CoreML encoder did not return audio embeddings";
            return false;
        }
        return copy_valid_frames(value.multiArrayValue, frames, out, embed_dim, error);
    }
}

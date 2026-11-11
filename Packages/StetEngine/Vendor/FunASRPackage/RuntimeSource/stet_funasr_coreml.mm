#import <CoreML/CoreML.h>
#import <Foundation/Foundation.h>
#include "stet_funasr_coreml.hpp"
#include <algorithm>
#include <cmath>
#include <mutex>
#include <stdexcept>

namespace {
constexpr int kFeatures=560, kEmbedding=1024, kBucketCount=4;
constexpr int kBucketFrames[kBucketCount]={64, 128, 256, 512};
std::runtime_error failure(NSError *error) {
    return std::runtime_error(error ? error.localizedDescription.UTF8String : "Core ML operation failed");
}
MLMultiArray *array(NSArray<NSNumber *> *shape) {
    NSError *error=nil;
    auto result=[[MLMultiArray alloc] initWithShape:shape dataType:MLMultiArrayDataTypeFloat32 error:&error];
    if (!result) throw failure(error);
    return result;
}
bool matches(MLFeatureDescription *description, NSArray<NSNumber *> *shape) {
    return description.type==MLFeatureTypeMultiArray &&
        description.multiArrayConstraint.dataType==MLMultiArrayDataTypeFloat32 &&
        [description.multiArrayConstraint.shape isEqualToArray:shape];
}
int bucketIndexForFrames(int frames) {
    for (int i=0; i<kBucketCount; ++i) {
        if (frames<=kBucketFrames[i]) return i;
    }
    return -1;
}
struct BucketSlot {
    int frames=0;
    MLMultiArray *features=nil;
    MLMultiArray *mask=nil;
    MLMultiArray *bias=nil;
    MLDictionaryFeatureProvider *input=nil;
};
}
struct StetCoreMLEncoder::Impl {
    std::mutex mutex;
    MLModel *model=nil;
    BucketSlot buckets[kBucketCount];

    BucketSlot &ensureBucket(int index) {
        auto &slot=buckets[index];
        const int kFrames=kBucketFrames[index];
        if (slot.input && slot.frames==kFrames) return slot;
        auto *features=array(@[@1,@560,@1,@(kFrames)]);
        auto *mask=array(@[@1,@1,@1,@(kFrames)]);
        auto *bias=array(@[@1,@(kFrames),@1,@1]);
        NSError *input_error=nil;
        auto *provider=[[MLDictionaryFeatureProvider alloc] initWithDictionary:@{
            @"positioned_features":features, @"valid_mask":mask, @"attention_bias":bias
        } error:&input_error];
        if (!provider) throw failure(input_error);
        slot.frames=kFrames;
        slot.features=features;
        slot.mask=mask;
        slot.bias=bias;
        slot.input=provider;
        return slot;
    }
};
StetCoreMLEncoder::StetCoreMLEncoder(const char *path, bool prewarm):impl(std::make_unique<Impl>()) {
    @autoreleasepool {
        MLModelConfiguration *config=[MLModelConfiguration new];
        config.computeUnits=MLComputeUnitsCPUAndNeuralEngine;
        NSError *error=nil;
        impl->model=[MLModel modelWithContentsOfURL:[NSURL fileURLWithPath:[NSString stringWithUTF8String:path]]
                                     configuration:config error:&error];
        if (!impl->model) throw failure(error);
        auto description=impl->model.modelDescription;
        NSDictionary *metadata=description.metadata[MLModelCreatorDefinedKey];
        if (![metadata[@"stet.encoder.contract"] isEqual:@"nano-gguf-ane-v1-buckets"] ||
            !matches(description.inputDescriptionsByName[@"positioned_features"],@[@1,@560,@1,@128]) ||
            !matches(description.inputDescriptionsByName[@"valid_mask"],@[@1,@1,@1,@128]) ||
            !matches(description.inputDescriptionsByName[@"attention_bias"],@[@1,@128,@1,@1]) ||
            description.outputDescriptionsByName[@"audio_embeds"].type!=MLFeatureTypeMultiArray ||
            description.outputDescriptionsByName[@"audio_embeds"].multiArrayConstraint.dataType!=MLMultiArrayDataTypeFloat32)
            throw std::runtime_error("incompatible Core ML encoder contract");
    }
    if (prewarm) warmup();
}
StetCoreMLEncoder::~StetCoreMLEncoder()=default;
void StetCoreMLEncoder::warmup() {
    std::lock_guard<std::mutex> lock(impl->mutex);
    const float silence=logf(1.1920929e-07f)*sqrtf(512.0f);
    const double increment=log(10000.0)/(kFeatures/2.0-1.0);
    for (int index=0; index<kBucketCount; ++index) {
        @autoreleasepool {
            auto &slot=impl->ensureBucket(index);
            const int kFrames=slot.frames;
            auto *input=static_cast<float *>(slot.features.dataPointer);
            auto *mask=static_cast<float *>(slot.mask.dataPointer);
            auto *bias=static_cast<float *>(slot.bias.dataPointer);
            for (int t=0; t<kFrames; ++t) {
                mask[t]=1.0f;
                bias[t]=0.0f;
            }
            for (int d=0; d<kFeatures/2; ++d) {
                double inverse=exp(-d*increment);
                for (int t=0; t<kFrames; ++t) {
                    double position=(t+1)*inverse;
                    input[d*kFrames+t]=silence+static_cast<float>(sin(position));
                    input[(d+kFeatures/2)*kFrames+t]=silence+static_cast<float>(cos(position));
                }
            }
            NSError *error=nil;
            auto prediction=[impl->model predictionFromFeatures:slot.input error:&error];
            if (!prediction) throw failure(error);
            auto output=[prediction featureValueForName:@"audio_embeds"].multiArrayValue;
            if (!output || output.dataType!=MLMultiArrayDataTypeFloat32 ||
                ![output.shape isEqualToArray:@[@1,@1024,@1,@(kFrames)]])
                throw std::runtime_error("unexpected Core ML encoder output");
            auto *source=static_cast<const float *>(output.dataPointer);
            const auto channel_stride=output.strides[1].integerValue, time_stride=output.strides[3].integerValue;
            for (int t=0; t<kFrames; ++t) for (int d=0; d<kEmbedding; ++d) {
                if (!std::isfinite(source[d*channel_stride+t*time_stride]))
                    throw std::runtime_error("non-finite Core ML encoder output");
            }
        }
    }
}
std::vector<float> StetCoreMLEncoder::encode(const std::vector<float> &features,int frames) {
    const int bucket_index=bucketIndexForFrames(frames);
    if (frames<1 || bucket_index<0 || features.size()!=static_cast<size_t>(frames*kFeatures))
        throw std::runtime_error("audio features exceed Core ML encoder shape");
    std::lock_guard<std::mutex> lock(impl->mutex);
    @autoreleasepool {
        auto &slot=impl->ensureBucket(bucket_index);
        const int kFrames=slot.frames;
        auto *input=static_cast<float *>(slot.features.dataPointer);
        auto *mask=static_cast<float *>(slot.mask.dataPointer);
        auto *bias=static_cast<float *>(slot.bias.dataPointer);
        std::fill(input,input+kFeatures*kFrames,0.0f);
        const float scale=sqrtf(512.0f);
        const double increment=log(10000.0)/(kFeatures/2.0-1.0);
        for(int t=0;t<kFrames;t++) {
            mask[t]=t<frames?1.0f:0.0f;
            bias[t]=t<frames?0.0f:-10000.0f;
        }
        for(int d=0;d<kFeatures/2;d++) {
            double inverse=exp(-d*increment);
            for(int t=0;t<frames;t++) {
                double position=(t+1)*inverse;
                input[d*kFrames+t]=features[t*kFeatures+d]*scale+static_cast<float>(sin(position));
                input[(d+kFeatures/2)*kFrames+t]=features[t*kFeatures+d+kFeatures/2]*scale+static_cast<float>(cos(position));
            }
        }
        NSError *error=nil;
        auto prediction=[impl->model predictionFromFeatures:slot.input error:&error];
        if (!prediction) throw failure(error);
        auto output=[prediction featureValueForName:@"audio_embeds"].multiArrayValue;
        if (!output || output.dataType!=MLMultiArrayDataTypeFloat32 ||
            ![output.shape isEqualToArray:@[@1,@1024,@1,@(kFrames)]])
            throw std::runtime_error("unexpected Core ML encoder output");
        auto *source=static_cast<const float *>(output.dataPointer);
        const auto channel_stride=output.strides[1].integerValue, time_stride=output.strides[3].integerValue;
        std::vector<float> result(static_cast<size_t>(frames*kEmbedding));
        for(int t=0;t<frames;t++) for(int d=0;d<kEmbedding;d++) {
            float value=source[d*channel_stride+t*time_stride];
            if (!std::isfinite(value)) throw std::runtime_error("non-finite Core ML encoder output");
            result[t*kEmbedding+d]=value;
        }
        return result;
    }
}

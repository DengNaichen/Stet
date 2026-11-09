#import <CoreML/CoreML.h>
#import <Foundation/Foundation.h>
#include "stet_funasr_coreml.hpp"
#include <algorithm>
#include <cmath>
#include <stdexcept>

namespace {
constexpr int kFeatures=560, kEmbedding=1024;
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
}
struct StetCoreMLEncoder::Impl {
    MLModel *model;
    MLMultiArray *features;
    MLMultiArray *mask;
    MLMultiArray *bias;
    MLDictionaryFeatureProvider *input;
    int bucket=0;
};
StetCoreMLEncoder::StetCoreMLEncoder(const char *path):impl(std::make_unique<Impl>()) {
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
}
StetCoreMLEncoder::~StetCoreMLEncoder()=default;
std::vector<float> StetCoreMLEncoder::encode(const std::vector<float> &features,int frames) {
    if (frames<1 || frames>512 || features.size()!=static_cast<size_t>(frames*kFeatures))
        throw std::runtime_error("audio features exceed Core ML encoder shape");
    @autoreleasepool {
        int kFrames=64;
        while(kFrames<frames) kFrames*=2;
        if(impl->bucket!=kFrames){
            impl->features=array(@[@1,@560,@1,@(kFrames)]);
            impl->mask=array(@[@1,@1,@1,@(kFrames)]);
            impl->bias=array(@[@1,@(kFrames),@1,@1]);
            NSError *input_error=nil;
            impl->input=[[MLDictionaryFeatureProvider alloc] initWithDictionary:@{
                @"positioned_features":impl->features, @"valid_mask":impl->mask, @"attention_bias":impl->bias
            } error:&input_error];
            if (!impl->input) throw failure(input_error);
            impl->bucket=kFrames;
        }
        auto *input=static_cast<float *>(impl->features.dataPointer);
        auto *mask=static_cast<float *>(impl->mask.dataPointer);
        auto *bias=static_cast<float *>(impl->bias.dataPointer);
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
        auto prediction=[impl->model predictionFromFeatures:impl->input error:&error];
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

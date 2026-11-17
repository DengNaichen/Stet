#pragma once
#include <memory>
#include <string>
#include <vector>

// Owns a model and prediction buffers per input-shape bucket; thread-safe across contexts.
class StetCoreMLEncoder {
public:
    explicit StetCoreMLEncoder(const char *compiled_path, bool prewarm = false);
    ~StetCoreMLEncoder();
    void warmup();
    std::vector<float> encode(const std::vector<float> &features, int frames);
private:
    struct Impl;
    std::unique_ptr<Impl> impl;
};

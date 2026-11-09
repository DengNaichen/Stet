#pragma once
#include <memory>
#include <string>
#include <vector>

// Owns the model and prediction buffers; used only on the recognizer's serial executor.
class StetCoreMLEncoder {
public:
    explicit StetCoreMLEncoder(const char *compiled_path);
    ~StetCoreMLEncoder();
    std::vector<float> encode(const std::vector<float> &features, int frames);
private:
    struct Impl;
    std::unique_ptr<Impl> impl;
};

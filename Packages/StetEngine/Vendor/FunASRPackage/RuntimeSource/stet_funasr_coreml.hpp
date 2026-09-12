#pragma once

#include <memory>
#include <string>
#include <vector>

bool stet_coreml_is_model_path(const char *path);

class StetCoreMLEncoder {
public:
    StetCoreMLEncoder();
    ~StetCoreMLEncoder();
    StetCoreMLEncoder(const StetCoreMLEncoder &) = delete;
    StetCoreMLEncoder &operator=(const StetCoreMLEncoder &) = delete;

    bool load(const char *path, std::string &error);
    bool encode(
        const float *fbank,
        int frames,
        int feature_dim,
        std::vector<float> &out,
        int &embed_dim,
        std::string &error
    );

private:
    struct Impl;
    std::unique_ptr<Impl> impl;
};

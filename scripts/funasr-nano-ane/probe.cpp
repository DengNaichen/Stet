// Diagnostic harness: exercises the exact production frontend, encoder and decoder.
#include "../../Packages/StetEngine/Vendor/FunASRPackage/RuntimeSource/stet_funasr.cpp"
#include <chrono>
#include <fstream>
#include <iostream>
#include <sys/resource.h>

using Clock = std::chrono::steady_clock;
static double seconds(Clock::time_point start) {
    return std::chrono::duration<double>(Clock::now() - start).count();
}
static void save(const std::string &path, const std::vector<float> &values) {
    std::ofstream stream(path, std::ios::binary);
    stream.write(reinterpret_cast<const char *>(values.data()), values.size() * sizeof(float));
    if (!stream) throw std::runtime_error("cannot write " + path);
}
int main(int argc, char **argv) {
    try {
        if (argc != 5 && argc != 6) throw std::runtime_error("usage: probe MODEL_DIR AUDIO.wav OUTPUT_PREFIX REPEATS [COREML_MODEL]");
        std::string dir=argv[1], prefix=argv[3];
        int repeats=std::stoi(argv[4]);
        enc_model encoder;
        auto start=Clock::now();
        std::unique_ptr<StetCoreMLEncoder> coreml;
        if(argc==6) coreml=std::make_unique<StetCoreMLEncoder>(argv[5]);
        else if (!load_enc((dir+"/funasr-encoder-f16.gguf").c_str(),encoder)) throw std::runtime_error("load encoder failed");
        double load=seconds(start);
        std::vector<float> wav;
        if (!funasr_load_audio_16k_mono(argv[2],wav)) throw std::runtime_error("load audio failed");
        int T=0,D=0;
        auto features=compute_fbank(wav,T);
        save(prefix+".features.f32",features);
        std::vector<double> timings;
        for(int i=0;i<repeats;i++) {
            start=Clock::now();
            D=1024;
            auto output=coreml ? coreml->encode(features,T) : run_encoder(encoder,features,T,560,D,4);
            timings.push_back(seconds(start));
            if(i==0) save(prefix+".embeds.f32",output);
        }
        rusage usage{}; getrusage(RUSAGE_SELF,&usage);
        std::ofstream meta(prefix+".json");
        meta << "{\"frames\":" << T << ",\"dim\":" << D << ",\"audio_seconds\":" << wav.size()/16000.0
             << ",\"load_seconds\":" << load << ",\"peak_rss_bytes\":" << usage.ru_maxrss << ",\"encoder_seconds\":[";
        for(size_t i=0;i<timings.size();i++) meta << (i?",":"") << timings[i];
        meta << "]}\n";
        if(encoder.ctx_w) ggml_free(encoder.ctx_w);
        std::cout << "frames=" << T << " encoder_first_s=" << timings.front() << " peak_rss=" << usage.ru_maxrss << std::endl;
        return 0;
    } catch(const std::exception &e) { std::cerr << e.what() << std::endl; return 1; }
}

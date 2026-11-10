// Exercise bucket transitions on a single model instance against production CPU outputs.
#include "stet_funasr_coreml.hpp"
#include <cmath>
#include <fstream>
#include <iostream>
#include <stdexcept>
#include <vector>
static std::vector<float> read(const std::string &path) {
    std::ifstream file(path,std::ios::binary|std::ios::ate);
    auto bytes=file.tellg();
    if(bytes<=0 || bytes%sizeof(float)!=0) throw std::runtime_error("invalid fixture: "+path);
    std::vector<float> values(bytes/sizeof(float));file.seekg(0);
    file.read(reinterpret_cast<char *>(values.data()),bytes);
    if(!file) throw std::runtime_error("fixture read failed");
    return values;
}
int main(int argc,char **argv) {
    try {
        if(argc<3) throw std::runtime_error("usage: sequence-probe MODEL REFERENCE_PREFIX...");
        StetCoreMLEncoder model(argv[1]);
        for(int i=2;i<argc;i++) {
            auto input=read(std::string(argv[i])+".features.f32");
            auto expected=read(std::string(argv[i])+".embeds.f32");
            if(input.size()%560!=0) throw std::runtime_error("invalid feature shape");
            auto actual=model.encode(input,input.size()/560);
            if(actual.size()!=expected.size()) throw std::runtime_error("output shape mismatch");
            double minimum=1;
            for(size_t t=0;t<actual.size()/1024;t++) {
                double dot=0,aa=0,bb=0;
                for(size_t d=0;d<1024;d++) {
                    double a=actual[t*1024+d],b=expected[t*1024+d];
                    if(!std::isfinite(a)) throw std::runtime_error("non-finite output");
                    dot+=a*b;aa+=a*a;bb+=b*b;
                }
                double cosine=dot/std::sqrt(aa*bb);
                if(!std::isfinite(cosine)||cosine<0.995) throw std::runtime_error("bucket-transition parity failed");
                minimum=std::min(minimum,cosine);
            }
            std::cout<<argv[i]<<" frames="<<input.size()/560<<" min_cosine="<<minimum<<std::endl;
        }
        return 0;
    } catch(const std::exception &e) {std::cerr<<e.what()<<std::endl;return 1;}
}

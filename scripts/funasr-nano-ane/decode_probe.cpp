// Inject saved encoder embeddings into the unchanged production llama.cpp decoder.
#include "../../Packages/StetEngine/Vendor/FunASRPackage/RuntimeSource/stet_funasr.cpp"
#include <chrono>
#include <fstream>
#include <iostream>
#include <iterator>
int main(int argc,char **argv) {
    if(argc!=3) { std::cerr << "usage: decode-probe MODEL_DIR EMBEDDINGS.f32\n"; return 2; }
    std::string dir=argv[1]; char error[512]{};
    auto *ctx=stet_funasr_create((dir+"/funasr-encoder-f16.gguf").c_str(),
        (dir+"/qwen3-0.6b-q4km.gguf").c_str(),(dir+"/fsmn-vad.gguf").c_str(),4,error,sizeof(error));
    if(!ctx) { std::cerr<<error<<std::endl; return 1; }
    try {
        std::ifstream file(argv[2],std::ios::binary|std::ios::ate);
        auto bytes=file.tellg();
        if(bytes<=0 || bytes%(1024*sizeof(float))!=0) throw std::runtime_error("invalid embeddings");
        std::vector<float> embeddings(bytes/sizeof(float)); file.seekg(0);
        file.read(reinterpret_cast<char*>(embeddings.data()),bytes);
        for(float v:embeddings) if(!std::isfinite(v)) throw std::runtime_error("non-finite embeddings");
        int T=embeddings.size()/1024;
        int ol=1+(T-3+2)/2; ol=1+(ol-3+2)/2; int n_audio=(ol-1)/2+1;
        auto prefix=prompt_tokens(ctx,nullptr); int n_past=0;
        auto start=std::chrono::steady_clock::now();
        if(decode_batch(ctx->llama,prefix.size(),prefix.data(),nullptr,0,n_past,false)!=0 ||
           decode_batch(ctx->llama,n_audio,nullptr,embeddings.data(),1024,n_past,false)!=0 ||
           decode_batch(ctx->llama,ctx->suffix.size(),ctx->suffix.data(),nullptr,0,n_past,true)!=0)
            throw std::runtime_error("prefill failed");
        std::string text;
        for(int i=0;i<512;i++) {
            auto token=llama_sampler_sample(ctx->sampler,ctx->llama,-1);
            if(llama_vocab_is_eog(ctx->vocab,token)) break;
            char buffer[256]; int n=llama_token_to_piece(ctx->vocab,token,buffer,sizeof(buffer),0,true);
            if(n>0) text.append(buffer,n);
            if(decode_batch(ctx->llama,1,&token,nullptr,0,n_past,true)!=0) throw std::runtime_error("decode failed");
        }
        std::cout<<text<<std::endl;
        std::cerr<<"decoder_seconds="<<std::chrono::duration<double>(std::chrono::steady_clock::now()-start).count()<<std::endl;
        stet_funasr_destroy(ctx); return 0;
    } catch(const std::exception &e) { std::cerr<<e.what()<<std::endl; stet_funasr_destroy(ctx); return 1; }
}

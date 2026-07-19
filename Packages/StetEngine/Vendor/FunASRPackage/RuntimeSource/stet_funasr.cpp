// Stet's in-process Fun-ASR-Nano runtime, derived from FunASR's funasr-cli.
//
//   wav(16k mono) -> kaldi fbank -> SAN-M encoder + adaptor (ggml) ->
//   low-frame-rate truncation -> [prefix tokens | audio embeds | suffix tokens]
//   -> Qwen3 LLM (llama.cpp) -> transcription.
//
// This is the whisper.cpp-style single-binary path: no Python at runtime.
//
//   funasr-cli --enc funasr-encoder.gguf -m qwen3-0.6b.gguf -a audio.wav

#include "ggml.h"
#include "ggml-cpu.h"
#include "ggml-alloc.h"
#include "ggml-backend.h"
#include "gguf.h"
#include "llama.h"
#include "stet_funasr.h"

#include <algorithm>
#include <cmath>
#include <cstdint>
#include <cstdio>
#include <cstdlib>
#include <cstring>
#include <exception>
#include <map>
#include <new>
#include <stdexcept>
#include <string>
#include <vector>

// any audio (wav/mp3/flac, any rate/channels) -> 16 kHz mono f32, via miniaudio
#define FUNASR_AUDIO_IMPLEMENTATION
#include "funasr_audio.h"
// built-in FSMN-VAD front end (single-binary --vad segmentation)
#include "funasr_vad.h"
#include <utility>

// ======================= kaldi fbank + LFR =======================
static const int FS=16000, WINLEN=400, SHIFT=160, NFFT=512, NMEL=80, LFR_M=7, LFR_N=6;
static const float PREEMPH=0.97f, LOWF=20.0f, HIGHF=8000.0f;
static inline float mel(float f){ return 1127.0f*logf(1.0f+f/700.0f); }
static void fft(std::vector<float>&re,std::vector<float>&im,int n){
    for(int i=1,j=0;i<n;i++){int b=n>>1;for(;j&b;b>>=1)j^=b;j^=b;if(i<j){std::swap(re[i],re[j]);std::swap(im[i],im[j]);}}
    for(int len=2;len<=n;len<<=1){double a=-2.0*M_PI/len;float wr=cosf(a),wi=sinf(a);
        for(int i=0;i<n;i+=len){float cr=1,ci=0;for(int k=0;k<len/2;k++){
            float ur=re[i+k],ui=im[i+k];float vr=re[i+k+len/2]*cr-im[i+k+len/2]*ci,vi=re[i+k+len/2]*ci+im[i+k+len/2]*cr;
            re[i+k]=ur+vr;im[i+k]=ui+vi;re[i+k+len/2]=ur-vr;im[i+k+len/2]=ui-vi;
            float n2=cr*wr-ci*wi;ci=cr*wi+ci*wr;cr=n2;}}}
}
// returns [T x 560] row-major, sets T
static std::vector<float> compute_fbank(std::vector<float> wav, int & T_out) {
    for (auto & v : wav) v *= 32768.0f;
    std::vector<float> win(WINLEN);
    for (int i=0;i<WINLEN;i++) win[i]=0.54f-0.46f*cosf(2.0f*M_PI*i/(WINLEN-1));
    const int NBIN=NFFT/2+1; float bw=(float)FS/NFFT, ml=mel(LOWF), mh=mel(HIGHF), dm=(mh-ml)/(NMEL+1);
    std::vector<std::vector<float>> fb(NMEL, std::vector<float>(NBIN,0.0f));
    for(int m=0;m<NMEL;m++){float L=ml+m*dm,C=ml+(m+1)*dm,R=ml+(m+2)*dm;
        for(int k=0;k<NBIN;k++){float mf=mel(bw*k); if(mf>L&&mf<R) fb[m][k]=mf<=C?(mf-L)/(C-L):(R-mf)/(R-C);}}
    int N=wav.size(); int T=(N-WINLEN)/SHIFT+1;
    std::vector<std::vector<float>> feat(T, std::vector<float>(NMEL));
    std::vector<float> re(NFFT),im(NFFT),fr(WINLEN);
    const float fl=1.1920929e-07f;
    for(int t=0;t<T;t++){const float*s=wav.data()+t*SHIFT;
        double mn=0;for(int i=0;i<WINLEN;i++)mn+=s[i];mn/=WINLEN;
        for(int i=0;i<WINLEN;i++)fr[i]=s[i]-(float)mn;
        for(int i=WINLEN-1;i>0;i--)fr[i]-=PREEMPH*fr[i-1];fr[0]-=PREEMPH*fr[0];
        for(int i=0;i<NFFT;i++){re[i]=i<WINLEN?fr[i]*win[i]:0.0f;im[i]=0.0f;}
        fft(re,im,NFFT);
        for(int m=0;m<NMEL;m++){float e=0;for(int k=0;k<NBIN;k++)if(fb[m][k]>0)e+=fb[m][k]*(re[k]*re[k]+im[k]*im[k]);
            feat[t][m]=logf(e>fl?e:fl);}}
    // LFR
    const int pad=(LFR_M-1)/2; int T_lfr=(T+LFR_N-1)/LFR_N;
    std::vector<std::vector<float>> pd; pd.reserve(T+pad+LFR_M);
    for(int i=0;i<pad;i++)pd.push_back(feat[0]);
    for(int t=0;t<T;t++)pd.push_back(feat[t]);
    while((int)pd.size()<(T_lfr-1)*LFR_N+LFR_M)pd.push_back(feat[T-1]);
    int D=LFR_M*NMEL; std::vector<float> out((size_t)T_lfr*D);
    for(int i=0;i<T_lfr;i++)for(int j=0;j<LFR_M;j++)
        memcpy(&out[(size_t)i*D+j*NMEL],pd[i*LFR_N+j].data(),NMEL*sizeof(float));
    T_out=T_lfr; return out;
}

// ======================= ggml SAN-M encoder + adaptor =======================
struct cfg { int d_model=512,n_head=4,num_blocks=50,tp_blocks=20,kernel=11,adp_llm=1024,adp_layers=2,adp_head=8; };
struct enc_model { cfg c; ggml_context*ctx_w=nullptr; std::map<std::string,ggml_tensor*> t;
    ggml_tensor* g(const std::string&n){auto it=t.find(n);if(it==t.end())throw std::runtime_error("encoder tensor missing: "+n);return it->second;} };
static const float LN_EPS=1e-5f;
static bool load_enc(const char*p, enc_model&m){
    gguf_init_params gp={false,&m.ctx_w}; gguf_context*g=gguf_init_from_file(p,gp); if(!g)return false;
    auto rd=[&](const char*k,int d){int i=gguf_find_key(g,k);return i<0?d:(int)gguf_get_val_u32(g,i);};
    m.c.d_model=rd("funasr.enc.output_size",512); m.c.n_head=rd("funasr.enc.attention_heads",4);
    m.c.num_blocks=rd("funasr.enc.num_blocks",50); m.c.tp_blocks=rd("funasr.enc.tp_blocks",20);
    m.c.kernel=rd("funasr.enc.kernel_size",11); m.c.adp_llm=rd("funasr.adp.llm_dim",1024);
    m.c.adp_layers=rd("funasr.adp.n_layer",2); m.c.adp_head=rd("funasr.adp.attention_heads",8);
    int n=gguf_get_n_tensors(g); for(int i=0;i<n;i++){const char*nm=gguf_get_tensor_name(g,i);m.t[nm]=ggml_get_tensor(m.ctx_w,nm);}
    gguf_free(g); return true;
}
static ggml_tensor* lin(ggml_context*c,ggml_tensor*w,ggml_tensor*b,ggml_tensor*x){auto y=ggml_mul_mat(c,w,x);return b?ggml_add(c,y,b):y;}
static ggml_tensor* lnorm(ggml_context*c,ggml_tensor*x,ggml_tensor*g,ggml_tensor*b){return ggml_add(c,ggml_mul(c,ggml_norm(c,x,LN_EPS),g),b);}
static ggml_tensor* sanm_attn(ggml_context*c,enc_model&m,const std::string&p,ggml_tensor*x,int T){
    const int D=m.c.d_model,H=m.c.n_head,dk=D/H,K=m.c.kernel;
    ggml_tensor*qkv=lin(c,m.g(p+"linear_q_k_v.weight"),m.g(p+"linear_q_k_v.bias"),x); size_t nb1=qkv->nb[1];
    ggml_tensor*q=ggml_cont(c,ggml_view_2d(c,qkv,D,T,nb1,0));
    ggml_tensor*k=ggml_cont(c,ggml_view_2d(c,qkv,D,T,nb1,(size_t)D*sizeof(float)));
    ggml_tensor*v=ggml_cont(c,ggml_view_2d(c,qkv,D,T,nb1,(size_t)2*D*sizeof(float)));
    const int pad=(K-1)/2; ggml_tensor*fk=m.g(p+"fsmn_block.weight");
    ggml_tensor*vp=ggml_pad_ext(c,v,0,0,pad,pad,0,0,0,0); ggml_tensor*fsmn=v;
    for(int j=0;j<K;j++){auto sl=ggml_view_2d(c,vp,D,T,vp->nb[1],(size_t)j*vp->nb[1]);
        auto wj=ggml_view_1d(c,fk,D,(size_t)j*fk->nb[1]); fsmn=ggml_add(c,fsmn,ggml_mul(c,ggml_cont(c,sl),wj));}
    q=ggml_permute(c,ggml_reshape_3d(c,q,dk,H,T),0,2,1,3); k=ggml_permute(c,ggml_reshape_3d(c,k,dk,H,T),0,2,1,3);
    ggml_tensor*vh=ggml_cont(c,ggml_permute(c,ggml_reshape_3d(c,v,dk,H,T),1,2,0,3));
    ggml_tensor*kq=ggml_soft_max(c,ggml_scale(c,ggml_mul_mat(c,k,q),1.0f/sqrtf((float)dk)));
    ggml_tensor*o=ggml_cont_2d(c,ggml_permute(c,ggml_mul_mat(c,vh,kq),0,2,1,3),D,T);
    return ggml_add(c,lin(c,m.g(p+"linear_out.weight"),m.g(p+"linear_out.bias"),o),fsmn);
}
static ggml_tensor* sanm_layer(ggml_context*c,enc_model&m,const std::string&p,ggml_tensor*x,int T,bool res){
    auto r=x; auto h=lnorm(c,x,m.g(p+"norm1.weight"),m.g(p+"norm1.bias"));
    auto sa=sanm_attn(c,m,p+"self_attn.",h,T); x=res?ggml_add(c,r,sa):sa; r=x;
    h=lnorm(c,x,m.g(p+"norm2.weight"),m.g(p+"norm2.bias"));
    h=lin(c,m.g(p+"feed_forward.w_1.weight"),m.g(p+"feed_forward.w_1.bias"),h); h=ggml_relu(c,h);
    h=lin(c,m.g(p+"feed_forward.w_2.weight"),m.g(p+"feed_forward.w_2.bias"),h); return ggml_add(c,r,h);
}
static ggml_tensor* adp_layer(ggml_context*c,enc_model&m,const std::string&p,ggml_tensor*x,int T){
    const int D=m.c.adp_llm,H=m.c.adp_head,dk=D/H; auto r=x;
    auto h=lnorm(c,x,m.g(p+"norm1.weight"),m.g(p+"norm1.bias"));
    auto q=ggml_permute(c,ggml_reshape_3d(c,lin(c,m.g(p+"self_attn.linear_q.weight"),m.g(p+"self_attn.linear_q.bias"),h),dk,H,T),0,2,1,3);
    auto k=ggml_permute(c,ggml_reshape_3d(c,lin(c,m.g(p+"self_attn.linear_k.weight"),m.g(p+"self_attn.linear_k.bias"),h),dk,H,T),0,2,1,3);
    auto vh=ggml_cont(c,ggml_permute(c,ggml_reshape_3d(c,lin(c,m.g(p+"self_attn.linear_v.weight"),m.g(p+"self_attn.linear_v.bias"),h),dk,H,T),1,2,0,3));
    auto kq=ggml_soft_max(c,ggml_scale(c,ggml_mul_mat(c,k,q),1.0f/sqrtf((float)dk)));
    auto o=ggml_cont_2d(c,ggml_permute(c,ggml_mul_mat(c,vh,kq),0,2,1,3),D,T);
    x=ggml_add(c,r,lin(c,m.g(p+"self_attn.linear_out.weight"),m.g(p+"self_attn.linear_out.bias"),o)); r=x;
    h=lnorm(c,x,m.g(p+"norm2.weight"),m.g(p+"norm2.bias"));
    h=lin(c,m.g(p+"feed_forward.w_1.weight"),m.g(p+"feed_forward.w_1.bias"),h); h=ggml_relu(c,h);
    h=lin(c,m.g(p+"feed_forward.w_2.weight"),m.g(p+"feed_forward.w_2.bias"),h); return ggml_add(c,r,h);
}
static void add_posenc(std::vector<float>&x,int T,int depth){
    double inc=log(10000.0)/(depth/2.0-1.0);
    for(int t=0;t<T;t++){double pos=t+1;for(int i=0;i<depth/2;i++){double its=exp(i*-inc),st=pos*its;
        x[(size_t)t*depth+i]+=(float)sin(st);x[(size_t)t*depth+depth/2+i]+=(float)cos(st);}}
}
// fbank [T x F] -> adaptor out [T x adp_llm] row-major
static std::vector<float> run_encoder(enc_model&m,std::vector<float> fbank,int T,int F,int&Dout,int thread_count){
    float sc=sqrtf((float)m.c.d_model); for(auto&v:fbank)v*=sc; add_posenc(fbank,T,F);
    ggml_backend_t be=ggml_backend_cpu_init();
    ggml_init_params cp={(size_t)1024*1024*1024,nullptr,true}; ggml_context*c=ggml_init(cp);
    ggml_tensor*inp=ggml_new_tensor_2d(c,GGML_TYPE_F32,F,T); ggml_set_input(inp);
    ggml_tensor*x=sanm_layer(c,m,"audio_encoder.encoders0.0.",inp,T,false);
    for(int i=0;i<m.c.num_blocks-1;i++) x=sanm_layer(c,m,"audio_encoder.encoders."+std::to_string(i)+".",x,T,true);
    x=lnorm(c,x,m.g("audio_encoder.after_norm.weight"),m.g("audio_encoder.after_norm.bias"));
    for(int i=0;i<m.c.tp_blocks;i++) x=sanm_layer(c,m,"audio_encoder.tp_encoders."+std::to_string(i)+".",x,T,true);
    x=lnorm(c,x,m.g("audio_encoder.tp_norm.weight"),m.g("audio_encoder.tp_norm.bias"));
    x=lin(c,m.g("audio_adaptor.linear1.weight"),m.g("audio_adaptor.linear1.bias"),x); x=ggml_relu(c,x);
    x=lin(c,m.g("audio_adaptor.linear2.weight"),m.g("audio_adaptor.linear2.bias"),x);
    for(int i=0;i<m.c.adp_layers;i++) x=adp_layer(c,m,"audio_adaptor.blocks."+std::to_string(i)+".",x,T);
    ggml_set_output(x);
    ggml_cgraph*gf=ggml_new_graph_custom(c,32768,false); ggml_build_forward_expand(gf,x);
    ggml_gallocr_t ga=ggml_gallocr_new(ggml_backend_cpu_buffer_type()); ggml_gallocr_alloc_graph(ga,gf);
    ggml_backend_tensor_set(inp,fbank.data(),0,ggml_nbytes(inp));
    ggml_backend_cpu_set_n_threads(be,thread_count); int compute_status=ggml_backend_graph_compute(be,gf);
    if(compute_status!=GGML_STATUS_SUCCESS){
        ggml_gallocr_free(ga); ggml_free(c); ggml_backend_free(be);
        throw std::runtime_error("encoder graph computation failed");
    }
    Dout=(int)x->ne[0]; std::vector<float> out((size_t)Dout*T); ggml_backend_tensor_get(x,out.data(),0,ggml_nbytes(x));
    ggml_gallocr_free(ga); ggml_free(c); ggml_backend_free(be); return out;
}

// ======================= LLM (llama.cpp) =======================
static int decode_batch(llama_context*ctx,int n,llama_token*tok,float*embd,int n_embd,int&n_past,bool last_logits){
    std::vector<llama_pos> pos(n); std::vector<int32_t> nsid(n,1);
    std::vector<llama_seq_id> s0(1,0); std::vector<llama_seq_id*> sid(n); std::vector<int8_t> lg(n,0);
    for(int i=0;i<n;i++){pos[i]=n_past+i;sid[i]=s0.data();}
    if(last_logits) lg[n-1]=1;
    llama_batch b={n,tok,embd,pos.data(),nsid.data(),sid.data(),lg.data()};
    int r=llama_decode(ctx,b); n_past+=n; return r;
}

struct stet_funasr_context {
    enc_model encoder;
    llama_model *model = nullptr;
    llama_context *llama = nullptr;
    llama_sampler *sampler = nullptr;
    const llama_vocab *vocab = nullptr;
    std::vector<llama_token> prefix;
    std::vector<llama_token> suffix;
    std::string vad_path;
    int thread_count = 1;
};

static void set_error(char *buffer,size_t buffer_size,const std::string&message){
    if(buffer==nullptr||buffer_size==0)return;
    snprintf(buffer,buffer_size,"%s",message.c_str());
}

static void runtime_log_callback(enum ggml_log_level level,const char*text,void*){
    if(level==GGML_LOG_LEVEL_ERROR)fprintf(stderr,"%s",text);
}

static std::vector<llama_token> tokenize(const llama_vocab*vocab,const char*text){
    int n=-llama_tokenize(vocab,text,strlen(text),nullptr,0,false,true);
    if(n<=0)throw std::runtime_error("prompt tokenization failed");
    std::vector<llama_token> tokens(n);
    if(llama_tokenize(vocab,text,strlen(text),tokens.data(),n,false,true)<0)
        throw std::runtime_error("prompt tokenization failed");
    return tokens;
}

static void destroy_context(stet_funasr_context*context){
    if(context==nullptr)return;
    if(context->sampler)llama_sampler_free(context->sampler);
    if(context->llama)llama_free(context->llama);
    if(context->model)llama_model_free(context->model);
    if(context->encoder.ctx_w)ggml_free(context->encoder.ctx_w);
    delete context;
}

extern "C" stet_funasr_context *stet_funasr_create(
    const char *encoder_path,const char *language_model_path,const char *vad_path,
    int thread_count,char *error_buffer,size_t error_buffer_size){
    if(!encoder_path||!language_model_path||!vad_path){
        set_error(error_buffer,error_buffer_size,"model paths are required");
        return nullptr;
    }
    auto context=new(std::nothrow) stet_funasr_context();
    if(!context){set_error(error_buffer,error_buffer_size,"unable to allocate runtime");return nullptr;}
    try{
        context->thread_count=std::max(1,thread_count);
        context->vad_path=vad_path;
        ggml_time_init();
        llama_log_set(runtime_log_callback,nullptr);
        if(!load_enc(encoder_path,context->encoder))throw std::runtime_error("encoder model could not be loaded");
        ggml_backend_load_all();
        llama_model_params mp=llama_model_default_params(); mp.n_gpu_layers=0;
        context->model=llama_model_load_from_file(language_model_path,mp);
        if(!context->model)throw std::runtime_error("language model could not be loaded");
        context->vocab=llama_model_get_vocab(context->model);
        llama_context_params cp=llama_context_default_params();
        cp.n_ctx=2048; cp.n_batch=512; cp.n_ubatch=512;
        cp.n_threads=context->thread_count; cp.n_threads_batch=context->thread_count;
        context->llama=llama_init_from_model(context->model,cp);
        if(!context->llama)throw std::runtime_error("language model context could not be created");
        context->sampler=llama_sampler_chain_init(llama_sampler_chain_default_params());
        if(!context->sampler)throw std::runtime_error("language model sampler could not be created");
        llama_sampler_chain_add(context->sampler,llama_sampler_init_greedy());
        const char*prefix="<|im_start|>system\nYou are a helpful assistant.<|im_end|>\n<|im_start|>user\n语音转写：";
        const char*suffix="<|im_end|>\n<|im_start|>assistant\n";
        context->prefix=tokenize(context->vocab,prefix);
        context->suffix=tokenize(context->vocab,suffix);
        return context;
    }catch(const std::exception&error){
        set_error(error_buffer,error_buffer_size,error.what()); destroy_context(context); return nullptr;
    }
}

extern "C" stet_funasr_status stet_funasr_transcribe(
    stet_funasr_context *context,const char *audio_path,int maximum_tokens,
    char **output_text,char *error_buffer,size_t error_buffer_size){
    if(!context||!audio_path||!output_text){
        set_error(error_buffer,error_buffer_size,"runtime, audio path, and output are required");
        return STET_FUNASR_INVALID_ARGUMENT;
    }
    *output_text=nullptr;
    try{
        std::vector<float>wav;
        if(!funasr_load_audio_16k_mono(audio_path,wav)){
            set_error(error_buffer,error_buffer_size,"audio file could not be decoded");
            return STET_FUNASR_AUDIO_LOAD_FAILED;
        }
        std::vector<std::pair<int,int>>segments;
        if(!funasr_vad_segments(context->vad_path,wav,30000,segments)){
            set_error(error_buffer,error_buffer_size,"voice activity detection failed");
            return STET_FUNASR_VAD_FAILED;
        }
        std::string full;
        const int token_limit=maximum_tokens>0?maximum_tokens:512;
        for(auto&segment:segments){
            int off=(int)((int64_t)segment.first*FS/1000);
            int end=(int)((int64_t)segment.second*FS/1000);
            end=std::min(end,(int)wav.size());
            if(end-off<WINLEN)continue;
            std::vector<float>samples(wav.begin()+off,wav.begin()+end);
            int T=0; auto fbank=compute_fbank(samples,T);
            int D=0; auto adaptor=run_encoder(context->encoder,fbank,T,560,D,context->thread_count);
            int ol=1+(T-3+2)/2; ol=1+(ol-3+2)/2; int n_audio=(ol-1)/2+1;
            llama_memory_clear(llama_get_memory(context->llama),true);
            llama_sampler_reset(context->sampler);
            int n_past=0;
            if(decode_batch(context->llama,(int)context->prefix.size(),context->prefix.data(),nullptr,0,n_past,false)!=0||
               decode_batch(context->llama,n_audio,nullptr,adaptor.data(),D,n_past,false)!=0||
               decode_batch(context->llama,(int)context->suffix.size(),context->suffix.data(),nullptr,0,n_past,true)!=0)
                throw std::runtime_error("language model prompt evaluation failed");
            llama_token token=llama_sampler_sample(context->sampler,context->llama,-1);
            for(int i=0;i<token_limit;i++){
                if(llama_vocab_is_eog(context->vocab,token))break;
                char buffer[256]; int count=llama_token_to_piece(context->vocab,token,buffer,sizeof(buffer),0,true);
                if(count>0)full.append(buffer,count);
                if(decode_batch(context->llama,1,&token,nullptr,0,n_past,true)!=0)
                    throw std::runtime_error("language model token evaluation failed");
                token=llama_sampler_sample(context->sampler,context->llama,-1);
            }
        }
        char*copy=(char*)malloc(full.size()+1);
        if(!copy){set_error(error_buffer,error_buffer_size,"unable to allocate transcription");return STET_FUNASR_OUT_OF_MEMORY;}
        memcpy(copy,full.c_str(),full.size()+1); *output_text=copy;
        return STET_FUNASR_OK;
    }catch(const std::bad_alloc&){
        set_error(error_buffer,error_buffer_size,"inference ran out of memory"); return STET_FUNASR_OUT_OF_MEMORY;
    }catch(const std::exception&error){
        set_error(error_buffer,error_buffer_size,error.what()); return STET_FUNASR_INFERENCE_FAILED;
    }
}

extern "C" void stet_funasr_free_text(char*text){free(text);}
extern "C" void stet_funasr_destroy(stet_funasr_context*context){destroy_context(context);}
extern "C" const char *stet_funasr_version(void){return "FunASR 9474bdb / llama.cpp 8086439";}

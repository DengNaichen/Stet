#include "stet_funasr.h"
#include <chrono>
#include <fstream>
#include <iomanip>
#include <iostream>
#include <sys/resource.h>
#include <mach/mach.h>
using Clock=std::chrono::steady_clock;
static double elapsed(Clock::time_point start) {return std::chrono::duration<double>(Clock::now()-start).count();}
static uint64_t footprint() {
    task_vm_info_data_t info{}; mach_msg_type_number_t count=TASK_VM_INFO_COUNT;
    return task_info(mach_task_self(),TASK_VM_INFO,reinterpret_cast<task_info_t>(&info),&count)==KERN_SUCCESS?info.phys_footprint:0;
}
int main(int argc,char **argv) {
    if(argc!=6) {std::cerr<<"usage: transcribe-probe ENCODER MODEL_DIR AUDIO REPEATS REPORT\n";return 2;}
    std::string dir=argv[2]; char error[512]{};
    auto baseline=footprint(); auto start=Clock::now();
    auto *ctx=stet_funasr_create(argv[1],(dir+"/qwen3-0.6b-q4km.gguf").c_str(),(dir+"/fsmn-vad.gguf").c_str(),4,error,sizeof(error));
    if(!ctx){std::cerr<<error<<std::endl;return 1;}
    std::ofstream report(argv[5]);
    report<<"load_seconds\t"<<elapsed(start)<<"\nbaseline_footprint_bytes\t"<<baseline
          <<"\nloaded_footprint_bytes\t"<<footprint()<<"\n";
    for(int i=0;i<std::stoi(argv[4]);i++) {
        char *text=nullptr; start=Clock::now();
        auto status=stet_funasr_transcribe(ctx,argv[3],512,nullptr,&text,error,sizeof(error));
        if(status!=STET_FUNASR_OK){std::cerr<<error<<std::endl;stet_funasr_destroy(ctx);return 1;}
        report<<"prediction_seconds\t"<<elapsed(start)<<"\ntranscript\t"<<text<<"\n";
        std::cout<<text<<std::endl;stet_funasr_free_text(text);
    }
    rusage usage{};getrusage(RUSAGE_SELF,&usage);
    report<<"backend\t"<<stet_funasr_encoder_backend(ctx)<<"\npeak_rss_bytes\t"<<usage.ru_maxrss
          <<"\nwarm_footprint_bytes\t"<<footprint()<<"\n";
    stet_funasr_destroy(ctx);
    report<<"released_footprint_bytes\t"<<footprint()<<"\n";
    return 0;
}

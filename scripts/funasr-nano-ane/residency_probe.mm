#import <Foundation/Foundation.h>
#include "stet_funasr_coreml.hpp"
#include <chrono>
#include <cstdio>
#include <cmath>
#include <mach/mach.h>
int main(int argc, char **argv) {
 if(argc!=3) return 2;
 @autoreleasepool {
  try {
   auto start=std::chrono::steady_clock::now();
   StetCoreMLEncoder encoder(argv[1],true);
   auto ms=[](auto start){return std::chrono::duration<double,std::milli>(std::chrono::steady_clock::now()-start).count();};
   printf("warmup_ms=%.3f\n",ms(start)); fflush(stdout);
   // The driver purges only this probe process's isolated E5 cache here.
   if(getchar()!='\n') return 4;
   for(int round=0;round<3;++round) for(int frames: {40,100,200,400,40,400,100,200}) {
    std::vector<float> input(frames*560);
    for(size_t i=0;i<input.size();++i)input[i]=0.01f*sin(i*0.01);
    start=std::chrono::steady_clock::now();
    auto output=encoder.encode(input,frames);
    if(round==0) {
     auto path=std::string(argv[2])+"/"+std::to_string(frames)+".f32";
     auto *file=fopen(path.c_str(),"wb");
     if(!file) return 5;
     const auto written=fwrite(output.data(),sizeof(float),output.size(),file);
     fclose(file);
     if(written!=output.size()) return 6;
    }
    double checksum=0;for(auto value:output){if(!std::isfinite(value))return 3;checksum+=value;}
    mach_task_basic_info_data_t info;mach_msg_type_number_t size=MACH_TASK_BASIC_INFO_COUNT;
    task_info(mach_task_self(),MACH_TASK_BASIC_INFO,(task_info_t)&info,&size);
    printf("round=%d frames=%d ms=%.3f rss_mb=%.1f checksum=%.9f\n",round,frames,ms(start),info.resident_size/1048576.0,checksum);fflush(stdout);
   }
  } catch(const std::exception &e){fprintf(stderr,"%s\n",e.what());return 1;}
 }
}

#ifndef STET_FUNASR_H
#define STET_FUNASR_H

#include <stddef.h>

#ifdef __cplusplus
extern "C" {
#endif

typedef struct stet_funasr_context stet_funasr_context;

typedef enum stet_funasr_status {
    STET_FUNASR_OK = 0,
    STET_FUNASR_INVALID_ARGUMENT = 1,
    STET_FUNASR_MODEL_LOAD_FAILED = 2,
    STET_FUNASR_AUDIO_LOAD_FAILED = 3,
    STET_FUNASR_VAD_FAILED = 4,
    STET_FUNASR_INFERENCE_FAILED = 5,
    STET_FUNASR_OUT_OF_MEMORY = 6
} stet_funasr_status;

stet_funasr_context *stet_funasr_create(
    const char *encoder_path,
    const char *language_model_path,
    const char *vad_path,
    int thread_count,
    char *error_buffer,
    size_t error_buffer_size
);

stet_funasr_status stet_funasr_transcribe(
    stet_funasr_context *context,
    const char *audio_path,
    int maximum_tokens,
    char **output_text,
    char *error_buffer,
    size_t error_buffer_size
);

void stet_funasr_free_text(char *text);
void stet_funasr_destroy(stet_funasr_context *context);
const char *stet_funasr_version(void);

#ifdef __cplusplus
}
#endif

#endif

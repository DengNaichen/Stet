import { validateAudioUpload } from "./request_validation.ts";
import { ApiError } from "./error.ts";
import { getRelayPolicy } from "./config.ts";

Deno.test("validateAudioUpload accepts plausible wav upload", () => {
  const file = new File([new Uint8Array(128_000)], "speech.wav", {
    type: "audio/wav",
  });

  const result = validateAudioUpload({
    file,
    audioDurationSeconds: 4,
    policy: getRelayPolicy(),
  });

  if (result.fileExtension !== "wav") {
    throw new Error(`expected wav extension, received ${result.fileExtension}`);
  }

  if (Math.round(result.observedBytesPerSecond) !== 32_000) {
    throw new Error(
      `expected 32000 bytes/s, received ${result.observedBytesPerSecond}`,
    );
  }
});

Deno.test("validateAudioUpload rejects unsupported formats", () => {
  const file = new File([new Uint8Array(1024)], "speech.mp3", {
    type: "audio/mpeg",
  });

  let thrown: unknown = null;
  try {
    validateAudioUpload({
      file,
      audioDurationSeconds: 4,
      policy: getRelayPolicy(),
    });
  } catch (error) {
    thrown = error;
  }

  if (
    !(thrown instanceof ApiError) || thrown.code !== "unsupported_audio_format"
  ) {
    throw new Error(
      `expected unsupported_audio_format, received ${String(thrown)}`,
    );
  }
});

Deno.test("validateAudioUpload rejects implausible durations", () => {
  const file = new File([new Uint8Array(1024)], "speech.wav", {
    type: "audio/wav",
  });

  let thrown: unknown = null;
  try {
    validateAudioUpload({
      file,
      audioDurationSeconds: 60,
      policy: getRelayPolicy(),
    });
  } catch (error) {
    thrown = error;
  }

  if (
    !(thrown instanceof ApiError) || thrown.code !== "invalid_audio_duration"
  ) {
    throw new Error(
      `expected invalid_audio_duration, received ${String(thrown)}`,
    );
  }
});

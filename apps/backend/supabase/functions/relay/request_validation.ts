import { ApiError } from "./error.ts";
import type { RelayPolicy } from "./config.ts";

const ALLOWED_CONTENT_TYPES = new Set([
  "audio/wav",
  "audio/x-wav",
  "audio/wave",
  "audio/m4a",
  "audio/mp4",
  "audio/x-m4a",
  "audio/aac",
]);

const ALLOWED_EXTENSIONS = new Set(["wav", "m4a"]);

export type AudioUploadAuditMetadata = {
  fileName: string;
  contentType: string | null;
  fileExtension: string | null;
  fileSizeBytes: number;
  claimedDurationSeconds: number;
  observedBytesPerSecond: number;
};

export function validateAudioUpload(args: {
  file: File;
  audioDurationSeconds: number;
  policy: RelayPolicy;
}): AudioUploadAuditMetadata {
  const fileName = args.file.name?.trim() || "audio";
  const contentType = normalizeContentType(args.file.type);
  const fileExtension = normalizeExtension(fileName);
  const fileSizeBytes = args.file.size;

  if (fileSizeBytes <= 0) {
    throw new ApiError(
      400,
      "empty_audio_file",
      "The transcription audio upload was empty.",
    );
  }

  if (fileSizeBytes > args.policy.maxAudioBytes) {
    throw new ApiError(
      413,
      "audio_file_too_large",
      "The transcription audio file exceeded the upload limit.",
    );
  }

  if (args.audioDurationSeconds > args.policy.maxAudioDurationSeconds) {
    throw new ApiError(
      400,
      "audio_duration_too_large",
      "The transcription audio duration exceeded the allowed limit.",
    );
  }

  if (
    (contentType && !ALLOWED_CONTENT_TYPES.has(contentType)) ||
    (fileExtension && !ALLOWED_EXTENSIONS.has(fileExtension))
  ) {
    throw new ApiError(
      415,
      "unsupported_audio_format",
      "The transcription audio format must be WAV or M4A.",
    );
  }

  if (!contentType && !fileExtension) {
    throw new ApiError(
      415,
      "unsupported_audio_format",
      "The transcription audio format must be WAV or M4A.",
    );
  }

  const observedBytesPerSecond = fileSizeBytes / args.audioDurationSeconds;
  if (
    observedBytesPerSecond < args.policy.minBytesPerSecond ||
    observedBytesPerSecond > args.policy.maxBytesPerSecond
  ) {
    throw new ApiError(
      400,
      "invalid_audio_duration",
      "The reported audio duration did not match the uploaded file.",
    );
  }

  return {
    fileName,
    contentType,
    fileExtension,
    fileSizeBytes,
    claimedDurationSeconds: args.audioDurationSeconds,
    observedBytesPerSecond,
  };
}

function normalizeContentType(value: string | undefined): string | null {
  const trimmed = value?.trim().toLowerCase();
  return trimmed ? trimmed : null;
}

function normalizeExtension(fileName: string): string | null {
  const lastDotIndex = fileName.lastIndexOf(".");
  if (lastDotIndex < 0 || lastDotIndex === fileName.length - 1) {
    return null;
  }

  const extension = fileName.slice(lastDotIndex + 1).trim().toLowerCase();
  return extension || null;
}

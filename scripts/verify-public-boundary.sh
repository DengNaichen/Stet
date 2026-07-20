#!/usr/bin/env bash

set -euo pipefail

readonly public_prefix="Public/Stet"
readonly github_blob_limit=100000000

repo_root="$(git rev-parse --show-toplevel)"
cd "${repo_root}"

if [[ ! -d "${public_prefix}" ]]; then
    echo "Missing public subtree: ${public_prefix}" >&2
    exit 1
fi

tracked_private_models="$(
    git ls-tree -r --name-only HEAD -- Private/StetMobile |
        grep -E '\.(onnx|gguf|safetensors|mlmodel|mlmodelc)(/|$)' || true
)"
if [[ -n "${tracked_private_models}" ]]; then
    echo "Private model payloads must remain local-only:" >&2
    printf '%s\n' "${tracked_private_models}" >&2
    exit 1
fi

split_commit="$(git subtree split --prefix="${public_prefix}")"
split_tree="$(git rev-parse "${split_commit}^{tree}")"
prefix_tree="$(git rev-parse "HEAD:${public_prefix}")"

if [[ "${split_tree}" != "${prefix_tree}" ]]; then
    echo "Public split tree does not match ${public_prefix}." >&2
    exit 1
fi

sensitive_paths="$(
    git ls-tree -r --name-only "${split_commit}" |
        grep -E '(^|/)Private(/|$)|(^|/)\.env($|\.)|\.(p8|pem|key)$' || true
)"
if [[ -n "${sensitive_paths}" ]]; then
    echo "Sensitive-looking paths found in public projection:" >&2
    printf '%s\n' "${sensitive_paths}" >&2
    exit 1
fi

oversized_blobs="$(
    git ls-tree -rl "${split_commit}" |
        awk -v limit="${github_blob_limit}" '$2 == "blob" && $4 >= limit { print $4, $5 }'
)"
if [[ -n "${oversized_blobs}" ]]; then
    echo "Public projection contains blobs at or above GitHub's 100 MB limit:" >&2
    printf '%s\n' "${oversized_blobs}" >&2
    exit 1
fi

if git show-ref --verify --quiet refs/remotes/public/main; then
    if ! git merge-base --is-ancestor refs/remotes/public/main "${split_commit}"; then
        echo "Public projection is not a fast-forward of public/main." >&2
        exit 1
    fi
fi

echo "Public projection verified: ${split_commit}"

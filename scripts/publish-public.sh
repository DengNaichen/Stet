#!/usr/bin/env bash

set -euo pipefail

readonly public_prefix="Public/Stet"
readonly expected_public_repository="github.com/DengNaichen/Stet.git"

repo_root="$(git rev-parse --show-toplevel)"
cd "${repo_root}"

if [[ -n "$(git status --porcelain)" ]]; then
    echo "Refusing to export from a dirty working tree." >&2
    exit 1
fi

public_url="$(git remote get-url public)"
if [[ "${public_url}" != *"${expected_public_repository}" ]]; then
    echo "Unexpected public remote: ${public_url}" >&2
    exit 1
fi

"${repo_root}/scripts/verify-public-boundary.sh"
split_commit="$(git subtree split --prefix="${public_prefix}")"

git fetch public main
if ! git merge-base --is-ancestor refs/remotes/public/main "${split_commit}"; then
    echo "Public export would not fast-forward public/main." >&2
    exit 1
fi

if [[ "${1:-}" == "--push" ]]; then
    git push public "${split_commit}:refs/heads/main"
    echo "Published ${split_commit} to public/main."
else
    echo "Public projection is ready: ${split_commit}"
    echo "Review it, then run: ./scripts/publish-public.sh --push"
fi

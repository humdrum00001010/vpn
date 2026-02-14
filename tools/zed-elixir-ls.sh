#!/usr/bin/env bash
set -euo pipefail

# Zed starts the Elixir language server from the worktree root. In this monorepo,
# the Mix project lives under ./coordinator, so we hop there before launching.
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

if [[ -f "${ROOT_DIR}/coordinator/mix.exs" ]]; then
  cd "${ROOT_DIR}/coordinator"
elif [[ -f "${ROOT_DIR}/mix.exs" ]]; then
  cd "${ROOT_DIR}"
else
  # Fallback: find the first mix.exs within 2 levels.
  MIX_DIR="$(find "${ROOT_DIR}" -maxdepth 2 -name mix.exs -print -quit | xargs -I{} dirname {} || true)"
  if [[ -n "${MIX_DIR}" ]]; then
    cd "${MIX_DIR}"
  fi
fi

exec elixir-ls

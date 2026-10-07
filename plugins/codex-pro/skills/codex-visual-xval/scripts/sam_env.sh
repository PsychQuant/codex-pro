#!/usr/bin/env bash
# sam_env.sh — the SAM 2.1 environment for /codex-pro:codex-visual-xval (#23).
#
#   sam_env.sh --check        prints installed / not_installed (exit 0 / 1)
#   sam_env.sh install        prints the download estimate and exits 3: consent first
#   sam_env.sh install --yes  creates ~/.codex-pro/sam-env with uv and downloads the model
#
# The skill asks the user before running `install --yes`; this script never installs on its
# own. Versions are pinned to the set the tracking was verified with (2026-10-07). A failed
# install removes the half-built environment, and only a directory carrying this script's
# marker is ever removed or rebuilt.

set -uo pipefail

ENV_DIR="$HOME/.codex-pro/sam-env"
MARKER="$ENV_DIR/.codex-pro-sam-env"
PYTHON_VERSION="3.13"
# torchvision is required by Sam2VideoProcessor; a first version without it passed
# `import torch, transformers` and still could not run SAM.
PINS=(torch==2.14.1 torchvision==0.29.1 transformers==5.19.0 numpy==2.5.3 pillow==10.4.0)
MODEL_ID="facebook/sam2.1-hiera-large"
MODEL_REVISION="665f8e2ad61cf5f53d65644ff27c8ee525124610"   # must match sam_track.py
# The weights live inside the environment, so the consent covers where they go and
# removing the environment removes them too.
export HF_HOME="$ENV_DIR/hf"
ESTIMATE="約 1 GB：模型權重 856 MB（2026-10-07 實測），torch 等套件約 0.1–0.2 GB（估計，依平台而異）"

check() {
  if [ -x "$ENV_DIR/bin/python" ] \
      && "$ENV_DIR/bin/python" -I -c "
import numpy, PIL, torch, torchvision
from huggingface_hub import try_to_load_from_cache
from transformers import Sam2VideoModel, Sam2VideoProcessor
Sam2VideoProcessor.from_pretrained('$MODEL_ID', revision='$MODEL_REVISION', local_files_only=True)
assert isinstance(try_to_load_from_cache('$MODEL_ID', 'model.safetensors', revision='$MODEL_REVISION'), str)
" >/dev/null 2>&1; then
    echo "installed path=$ENV_DIR"
    return 0
  fi
  echo "not_installed path=$ENV_DIR"
  return 1
}

install() {
  if [ "${1:-}" != "--yes" ]; then
    echo "consent_required: 安裝 SAM 2.1 環境到 ${ENV_DIR}（模型權重也放在 ${HF_HOME}），下載量${ESTIMATE}。"
    echo "使用者同意後，執行：sam_env.sh install --yes"
    exit 3
  fi
  if ! command -v uv >/dev/null 2>&1; then
    echo "error=uv_missing remediation=install uv (https://docs.astral.sh/uv/)"
    exit 2
  fi
  if check >/dev/null; then
    check
    exit 0
  fi
  if [ -e "$ENV_DIR" ]; then
    if [ ! -f "$MARKER" ]; then
      echo "error=foreign_directory path=$ENV_DIR detail=exists but was not created by sam_env.sh; not touching it"
      exit 2
    fi
    rm -rf "$ENV_DIR"   # our own broken environment: rebuild it
  fi
  mkdir -p "$(dirname "$ENV_DIR")"
  echo "installing: $ESTIMATE"
  if uv venv --python "$PYTHON_VERSION" "$ENV_DIR" \
      && touch "$MARKER" \
      && uv pip install --python "$ENV_DIR/bin/python" "${PINS[@]}" \
      && "$ENV_DIR/bin/python" -I -c "from huggingface_hub import snapshot_download; snapshot_download('$MODEL_ID', revision='$MODEL_REVISION')"; then
    check
    exit $?
  fi
  [ -f "$MARKER" ] && rm -rf "$ENV_DIR"
  echo "error=install_failed path=$ENV_DIR"
  exit 1
}

case "${1:-}" in
  --check) check; exit $? ;;
  install) install "${2:-}" ;;
  *) sed -n '2,12p' "$0" >&2; exit 64 ;;
esac

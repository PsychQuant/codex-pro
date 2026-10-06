# Third-Party Notices

## `codex-call`

This Claude plugin package includes a source snapshot at
`runtime/codex-call` from
[`PsychQuant/parallel-ai-agents`](https://github.com/PsychQuant/parallel-ai-agents):

- Upstream commit: `19564c1567a6110f8ebbafe0ae404984c0ef8745`
- Upstream path: `plugins/parallel-ai-agents/bin/codex-call`
- Copyright (c) 2026 Che Cheng
- License: MIT

The complete copyright and permission notice is included in this package's
[LICENSE](LICENSE). The snapshot remains byte-for-byte unchanged; its source,
Git blob, size, and SHA-256 are recorded in
[`references/codex-call-provenance.json`](references/codex-call-provenance.json).

This snapshot inherits upstream known issues #28 and #35 and uses an unstable
ChatGPT backend surface. Its inclusion does not make that runtime a stable
public API.

## SAM 2.1 model (`facebook/sam2.1-hiera-large`)

The tracking step of `/codex-pro:codex-visual-xval` uses Meta's SAM 2.1. This package does
**not** redistribute the model weights or code: `skills/codex-visual-xval/scripts/sam_env.sh`
downloads them from Hugging Face into the user's own cache, and only after the user agrees.
According to the Hugging Face model page metadata, the model is licensed Apache-2.0 (checked
2026-10-07). torch, torchvision, transformers, numpy and pillow are installed from PyPI by uv
into `~/.codex-pro/sam-env/`, each under its own license.

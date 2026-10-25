#!/usr/bin/env bash
# Stage 1: render the vLLM-native params artifact (vllm-params/v1).
set -euo pipefail

usage() {
  cat <<'EOF'
Usage: render-params.sh [-c CONFIG] [-o OUTFILE]

  -c, --config   Dynamic input / scenario config (default: vllm/params/single-h200-8gpu.json)
  -o, --out      Output file; omit to write to stdout
  -h, --help     Show this help

Paths are resolved relative to the repository root.
EOF
}

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
REPO="$(dirname -- "$SCRIPT_DIR")"
CONFIG="vllm/params/single-h200-8gpu.json"
OUTFILE=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    -c|--config)
      CONFIG="${2:-}"
      [[ -n "$CONFIG" ]] || { echo "missing value for $1" >&2; exit 2; }
      shift 2
      ;;
    -o|--out)
      OUTFILE="${2:-}"
      [[ -n "$OUTFILE" ]] || { echo "missing value for $1" >&2; exit 2; }
      shift 2
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      echo "unknown argument: $1" >&2
      usage >&2
      exit 2
      ;;
  esac
done

command -v jsonnet >/dev/null 2>&1 || { echo "jsonnet not found in PATH" >&2; exit 1; }
cd -- "$REPO"

if [[ -z "$OUTFILE" ]]; then
  jsonnet vllm/generate-params.jsonnet --tla-code-file "config=$CONFIG"
else
  mkdir -p -- "$(dirname -- "$OUTFILE")"
  jsonnet vllm/generate-params.jsonnet --tla-code-file "config=$CONFIG" > "$OUTFILE"
  echo "Wrote $OUTFILE"
fi

#!/usr/bin/env bash
# Stage 2: render CLI arguments/commands from a vLLM-native params artifact.
set -euo pipefail

usage() {
  cat <<'EOF'
Usage: render-cli.sh -p PARAMS [-o OUTFILE]

  -p, --params   Input params artifact (required), e.g. vllm/out/single.params.json
  -o, --out      Output file; omit to write to stdout
  -h, --help     Show this help

Paths are resolved relative to the repository root.
EOF
}

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
REPO="$(dirname -- "$SCRIPT_DIR")"
PARAMS=""
OUTFILE=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    -p|--params)
      PARAMS="${2:-}"
      [[ -n "$PARAMS" ]] || { echo "missing value for $1" >&2; exit 2; }
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

if [[ -z "$PARAMS" ]]; then
  echo "missing required argument: -p/--params" >&2
  usage >&2
  exit 2
fi

command -v jsonnet >/dev/null 2>&1 || { echo "jsonnet not found in PATH" >&2; exit 1; }
cd -- "$REPO"

if [[ ! -f "$PARAMS" ]]; then
  echo "params artifact not found: $PARAMS" >&2
  exit 1
fi

if [[ -z "$OUTFILE" ]]; then
  jsonnet vllm/render-cli.jsonnet --tla-code-file "params=$PARAMS"
else
  mkdir -p -- "$(dirname -- "$OUTFILE")"
  jsonnet vllm/render-cli.jsonnet --tla-code-file "params=$PARAMS" > "$OUTFILE"
  echo "Wrote $OUTFILE"
fi

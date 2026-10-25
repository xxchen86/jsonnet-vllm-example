#!/usr/bin/env bash
# Run all Jsonnet tests and render every scenario through both stages.
set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
REPO="$(dirname -- "$SCRIPT_DIR")"

command -v jsonnet >/dev/null 2>&1 || { echo "jsonnet not found in PATH" >&2; exit 1; }
command -v python3 >/dev/null 2>&1 || { echo "python3 not found in PATH" >&2; exit 1; }

cd -- "$REPO"

jsonnet vllm/params-tests.jsonnet > /dev/null
jsonnet vllm/cli-tests.jsonnet > /dev/null
jsonnet vllm/golden-tests.jsonnet > /dev/null
jsonnet vllm/launch-tests.jsonnet > /dev/null

out_dir="vllm/out/tests"
mkdir -p -- "$out_dir"

first_params=""
count=0

for scenario in vllm/params/*.json; do
  name="$(basename -- "$scenario" .json)"
  params_file="$out_dir/$name.params.json"
  cli_file="$out_dir/$name.cli.json"

  jsonnet vllm/generate-params.jsonnet --tla-code-file "config=$scenario" > "$params_file"
  python3 -I -m json.tool "$params_file" > /dev/null

  jsonnet vllm/render-cli.jsonnet --tla-code-file "params=$params_file" > "$cli_file"
  python3 -I -m json.tool "$cli_file" > /dev/null

  if [[ -z "$first_params" ]]; then
    first_params="$params_file"
  fi
  count=$((count + 1))
done

# A rendered params artifact is itself a valid low-level static template.
jsonnet vllm/generate-params.jsonnet --tla-code-file "template=$first_params" > /dev/null

# Negative checks: wrong-stage / invalid inputs must fail.
bad_params="$out_dir/bad.params.json"
printf '%s\n' '{"apiVersion":"vllm-params/v2"}' > "$bad_params"

if jsonnet vllm/render-cli.jsonnet --tla-code-file "params=$bad_params" > /dev/null 2>&1; then
  echo "ERROR: render-cli should reject an invalid apiVersion" >&2
  exit 1
fi

if jsonnet vllm/generate-params.jsonnet --tla-code-file "config=$first_params" > /dev/null 2>&1; then
  echo "ERROR: generate-params should reject a params artifact passed as config" >&2
  exit 1
fi

if jsonnet vllm/generate-params.jsonnet \
  --tla-code 'config={nodes:2,gpusPerNode:8,tensorParallel:5}' > /dev/null 2>&1; then
  echo "ERROR: generate-params should reject an invalid TP configuration" >&2
  exit 1
fi

rm -f -- "$bad_params"

echo "OK: params/cli/golden/launch tests passed; rendered $count scenarios through both stages."

#!/usr/bin/env bash
set -Eeuo pipefail

APP_NAME="Vast vLLM Deployer"
DEFAULT_IMAGE="vllm/vllm-openai:v0.10.0"
DEFAULT_TEMPLATE_HASH="e89723eb11d283d1b7e9091123d16f91"
DEFAULT_VAST_VLLM_TEMPLATE_HASH="e89723eb11d283d1b7e9091123d16f91"
DEFAULT_PORT="8000"
DEFAULT_DISK="120"
DEFAULT_GPU_COUNT="1"
DEFAULT_MIN_GPU_RAM="16"
DEFAULT_MIN_CUDA_VERSION="12.8"
DEFAULT_MIN_COMPUTE_CAP="750"
DEFAULT_MAX_PRICE=""
DEFAULT_VERIFIED="y"
DEFAULT_PRICING="on-demand"
DEFAULT_OFFER_LIMIT="10"
VAST_PROXY_USER="vastai"
VASTAI_VENV_DIR=".vastai-cli-venv"
DRY_RUN=0
NON_INTERACTIVE=0
VAST_API_KEY_INPUT=""
MODEL_ID=""
HF_TOKEN="${HF_TOKEN:-}"
GPU_COUNT=""
MIN_GPU_RAM=""
MAX_PRICE=""
MIN_CUDA_VERSION=""
MIN_COMPUTE_CAP=""
DISK_GB=""
VERIFIED_ONLY=""
PRICING_TYPE=""
EXTRA_VLLM_ARGS=""
OFFER_INDEX=""
TEMPLATE_HASH="$DEFAULT_TEMPLATE_HASH"

setup_colors() {
  if [[ -t 1 ]] && command -v tput >/dev/null 2>&1 && [[ "$(tput colors 2>/dev/null || echo 0)" -ge 8 ]]; then
    BOLD="$(tput bold)"
    DIM="$(tput dim)"
    RESET="$(tput sgr0)"
    RED="$(tput setaf 1)"
    GREEN="$(tput setaf 2)"
    YELLOW="$(tput setaf 3)"
    BLUE="$(tput setaf 4)"
    MAGENTA="$(tput setaf 5)"
    CYAN="$(tput setaf 6)"
  else
    BOLD=""; DIM=""; RESET=""; RED=""; GREEN=""; YELLOW=""; BLUE=""; MAGENTA=""; CYAN=""
  fi
}

say() { printf '%b\n' "$*"; }
info() { say "${BLUE}==>${RESET} $*"; }
ok() { say "${GREEN}OK${RESET} $*"; }
warn() { say "${YELLOW}WARN${RESET} $*"; }
fail() { say "${RED}ERROR${RESET} $*" >&2; exit 1; }

usage() {
  cat <<'EOF'
Usage:
  ./deploy-vllm-vast.sh [options]

Deploy a Hugging Face model on Vast.ai with vLLM and an OpenAI-compatible API.
Any missing required value is prompted interactively.

Examples:
  ./deploy-vllm-vast.sh --dry-run \
    --yes \
    --vast-api-key "$VAST_API_KEY" \
    --model Qwen/Qwen3-8B \
    --gpus 1 \
    --min-gpu-ram 18 \
    --disk 120 \
    --no-verified

  ./deploy-vllm-vast.sh \
    --yes \
    --vast-api-key "$VAST_API_KEY" \
    --model Qwen/Qwen3-8B \
    --gpus 1 \
    --min-gpu-ram 18 \
    --disk 120 \
    --no-verified \
    --offer-index 1

Options:
  --dry-run                 Install/auth/search and show deploy command, but do not rent.
  --yes, --non-interactive  Use defaults for missing optional values; fail on missing required values.
  --vast-api-key KEY        Vast.ai API key. Can also use VAST_API_KEY env var.
  --model MODEL_ID          Hugging Face model ID, e.g. Qwen/Qwen3-8B.
  --hf-token TOKEN          Hugging Face token for gated/private models. Can also use HF_TOKEN.
  --gpus N                  Number of GPUs. Default: 1.
  --min-gpu-ram GB          Minimum GPU RAM per GPU. Default: 16.
  --min-cuda-version N      Minimum CUDA version. Default: 12.8 for the default Vast vLLM template.
  --min-compute-cap N       Minimum CUDA compute capability x100. Default: 750.
  --max-price USD_PER_HOUR  Max hourly price. Blank means no cap.
  --disk GB                 Instance disk size. Default: 120.
  --template-hash HASH      Optional Vast template hash. Default: Vast-maintained vLLM template.
  --verified y|n            Filter to verified machines.
  --no-verified             Shortcut for --verified n.
  --pricing on-demand|bid   Pricing type. Default: on-demand.
  --extra-vllm-args ARGS    Extra args appended to vllm serve.
  --offer-index N           Offer table row to rent. Default prompt in live mode.
  -h, --help                Show this help.
EOF
}

parse_args() {
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --dry-run)
        DRY_RUN=1
        shift
        ;;
      --yes|--non-interactive)
        NON_INTERACTIVE=1
        shift
        ;;
      --vast-api-key)
        [[ $# -ge 2 ]] || fail "--vast-api-key requires a value."
        VAST_API_KEY_INPUT="$2"
        shift 2
        ;;
      --vast-api-key=*)
        VAST_API_KEY_INPUT="${1#*=}"
        shift
        ;;
      --model)
        [[ $# -ge 2 ]] || fail "--model requires a value."
        MODEL_ID="$2"
        shift 2
        ;;
      --model=*)
        MODEL_ID="${1#*=}"
        shift
        ;;
      --hf-token)
        [[ $# -ge 2 ]] || fail "--hf-token requires a value."
        HF_TOKEN="$2"
        shift 2
        ;;
      --hf-token=*)
        HF_TOKEN="${1#*=}"
        shift
        ;;
      --gpus)
        [[ $# -ge 2 ]] || fail "--gpus requires a value."
        GPU_COUNT="$2"
        shift 2
        ;;
      --gpus=*)
        GPU_COUNT="${1#*=}"
        shift
        ;;
      --min-gpu-ram)
        [[ $# -ge 2 ]] || fail "--min-gpu-ram requires a value."
        MIN_GPU_RAM="$2"
        shift 2
        ;;
      --min-gpu-ram=*)
        MIN_GPU_RAM="${1#*=}"
        shift
        ;;
      --max-price)
        [[ $# -ge 2 ]] || fail "--max-price requires a value."
        MAX_PRICE="$2"
        shift 2
        ;;
      --max-price=*)
        MAX_PRICE="${1#*=}"
        shift
        ;;
      --min-cuda-version)
        [[ $# -ge 2 ]] || fail "--min-cuda-version requires a value."
        MIN_CUDA_VERSION="$2"
        shift 2
        ;;
      --min-cuda-version=*)
        MIN_CUDA_VERSION="${1#*=}"
        shift
        ;;
      --min-compute-cap)
        [[ $# -ge 2 ]] || fail "--min-compute-cap requires a value."
        MIN_COMPUTE_CAP="$2"
        shift 2
        ;;
      --min-compute-cap=*)
        MIN_COMPUTE_CAP="${1#*=}"
        shift
        ;;
      --disk)
        [[ $# -ge 2 ]] || fail "--disk requires a value."
        DISK_GB="$2"
        shift 2
        ;;
      --disk=*)
        DISK_GB="${1#*=}"
        shift
        ;;
      --template-hash)
        [[ $# -ge 2 ]] || fail "--template-hash requires a value."
        TEMPLATE_HASH="$2"
        shift 2
        ;;
      --template-hash=*)
        TEMPLATE_HASH="${1#*=}"
        shift
        ;;
      --verified)
        [[ $# -ge 2 ]] || fail "--verified requires y or n."
        VERIFIED_ONLY="$2"
        shift 2
        ;;
      --verified=*)
        VERIFIED_ONLY="${1#*=}"
        shift
        ;;
      --no-verified)
        VERIFIED_ONLY="n"
        shift
        ;;
      --pricing)
        [[ $# -ge 2 ]] || fail "--pricing requires on-demand or bid."
        PRICING_TYPE="$2"
        shift 2
        ;;
      --pricing=*)
        PRICING_TYPE="${1#*=}"
        shift
        ;;
      --extra-vllm-args)
        [[ $# -ge 2 ]] || fail "--extra-vllm-args requires a value."
        EXTRA_VLLM_ARGS="$2"
        shift 2
        ;;
      --extra-vllm-args=*)
        EXTRA_VLLM_ARGS="${1#*=}"
        shift
        ;;
      --offer-index)
        [[ $# -ge 2 ]] || fail "--offer-index requires a value."
        OFFER_INDEX="$2"
        shift 2
        ;;
      --offer-index=*)
        OFFER_INDEX="${1#*=}"
        shift
        ;;
      -h|--help)
        usage
        exit 0
        ;;
      *)
        fail "Unknown option: $1. Use --help."
        ;;
    esac
  done
}

require_python() {
  command -v python3 >/dev/null 2>&1 || fail "python3 is required."
}

load_dotenv() {
  [[ -f .env ]] || return 0
  while IFS='=' read -r key value; do
    key="$(trim "${key:-}")"
    value="$(trim "${value:-}")"
    [[ -z "$key" || "$key" == \#* ]] && continue
    value="${value%\"}"
    value="${value#\"}"
    value="${value%\'}"
    value="${value#\'}"
    case "$key" in
      API_KEY|VAST_API_KEY|HF_TOKEN)
        if [[ -z "${!key:-}" ]]; then
          export "$key=$value"
        fi
        ;;
    esac
  done < .env
}

trim() {
  local value="$1"
  value="${value#"${value%%[![:space:]]*}"}"
  value="${value%"${value##*[![:space:]]}"}"
  printf '%s' "$value"
}

normalize_bool() {
  local value
  value="$(trim "$1")"
  case "$value" in
    y|Y|yes|YES|true|TRUE|1) printf 'y' ;;
    n|N|no|NO|false|FALSE|0) printf 'n' ;;
    *) printf '%s' "$value" ;;
  esac
}

prompt_if_empty() {
  local name="$1"
  local label="$2"
  local default="${3:-}"
  local secret="${4:-0}"
  local current="${!name:-}"

  if [[ -z "$current" ]]; then
    if [[ "$NON_INTERACTIVE" == "1" ]]; then
      printf -v "$name" '%s' "$default"
    else
      prompt "$name" "$label" "$default" "$secret"
    fi
  fi
}

prompt() {
  local name="$1"
  local label="$2"
  local default="${3:-}"
  local secret="${4:-0}"
  local value

  if [[ "$secret" == "1" ]]; then
    if [[ -n "$default" ]]; then
      printf '%b' "${CYAN}?${RESET} ${label} ${DIM}[already set; press enter to keep]${RESET}: "
    else
      printf '%b' "${CYAN}?${RESET} ${label}: "
    fi
    IFS= read -r -s value || true
    printf '\n'
  else
    if [[ -n "$default" ]]; then
      printf '%b' "${CYAN}?${RESET} ${label} ${DIM}[${default}]${RESET}: "
    else
      printf '%b' "${CYAN}?${RESET} ${label}: "
    fi
    IFS= read -r value || true
  fi

  if [[ -z "$value" ]]; then
    value="$default"
  fi
  printf -v "$name" '%s' "$value"
}

confirm_value() {
  local value="$1"
  [[ "$value" == "y" || "$value" == "Y" || "$value" == "yes" || "$value" == "YES" ]]
}

ensure_vastai() {
  if command -v vastai >/dev/null 2>&1; then
    return
  fi

  if [[ -x "${VASTAI_VENV_DIR}/bin/vastai" ]]; then
    export PATH="${PWD}/${VASTAI_VENV_DIR}/bin:${PATH}"
    return
  fi

  info "vastai CLI not found; installing into local virtualenv ${VASTAI_VENV_DIR}"
  python3 -m venv "$VASTAI_VENV_DIR"
  "${VASTAI_VENV_DIR}/bin/python" -m pip install --upgrade pip >/dev/null
  "${VASTAI_VENV_DIR}/bin/python" -m pip install vastai
  export PATH="${PWD}/${VASTAI_VENV_DIR}/bin:${PATH}"

  command -v vastai >/dev/null 2>&1 || fail "vastai installed but is not on PATH. Retry from the script directory or install Vast CLI manually."
}

vastai_cli() {
  vastai --api-key "$VAST_API_KEY" "$@"
}

generate_key() {
  if command -v openssl >/dev/null 2>&1; then
    printf 'sk-vast-%s\n' "$(openssl rand -hex 24)"
  else
    python3 -c 'import secrets; print("sk-vast-" + secrets.token_hex(24))'
  fi
}

json_extract_new_contract() {
  python3 -c '
import ast
import json
import re
import sys

raw = sys.stdin.read().strip()
if not raw:
    raise SystemExit(1)

data = None
for loader in (json.loads, ast.literal_eval):
    try:
        data = loader(raw)
        break
    except Exception:
        pass

if isinstance(data, dict):
    for key in ("new_contract", "contract_id", "id"):
        value = data.get(key)
        if value:
            print(value)
            raise SystemExit(0)

patterns = (
    r"[\"\047]?new_contract[\"\047]?\s*[:=]\s*([0-9]+)",
    r"[\"\047]?contract_id[\"\047]?\s*[:=]\s*([0-9]+)",
    r"\binstance\s+([0-9]+)\b",
)
for pattern in patterns:
    match = re.search(pattern, raw, re.IGNORECASE)
    if match:
        print(match.group(1))
        raise SystemExit(0)

raise SystemExit(1)
'
}

json_extract_template_hash() {
  python3 -c '
import ast
import json
import re
import sys

raw = sys.stdin.read().strip()
if not raw:
    raise SystemExit(1)

data = None
for loader in (json.loads, ast.literal_eval):
    try:
        data = loader(raw)
        break
    except Exception:
        pass

def walk(obj):
    if isinstance(obj, dict):
        yield obj
        for value in obj.values():
            yield from walk(value)
    elif isinstance(obj, list):
        for value in obj:
            yield from walk(value)

if data is not None:
    for item in walk(data):
        for key in ("hash_id", "template_hash", "template_hash_id"):
            value = item.get(key) if isinstance(item, dict) else None
            if value:
                print(value)
                raise SystemExit(0)

patterns = (
    r"[\"\047]?hash_id[\"\047]?\s*[:=]\s*[\"\047]([a-fA-F0-9]{16,})[\"\047]",
    r"[\"\047]?template_hash(?:_id)?[\"\047]?\s*[:=]\s*[\"\047]([a-fA-F0-9]{16,})[\"\047]",
)
for pattern in patterns:
    match = re.search(pattern, raw)
    if match:
        print(match.group(1))
        raise SystemExit(0)

raise SystemExit(1)
'
}

json_instance_status() {
  python3 -c '
import json, sys
data = json.load(sys.stdin)
if isinstance(data, list) and data:
    data = data[0]
if not isinstance(data, dict):
    raise SystemExit(1)
for key in ("actual_status", "status", "state"):
    value = data.get(key)
    if value:
        print(str(value))
        raise SystemExit(0)
cur_state = data.get("cur_state")
status_msg = str(data.get("status_msg", ""))
if cur_state == "running" and status_msg.lower().startswith("success"):
    print("running")
    raise SystemExit(0)
if cur_state:
    print("loading")
    raise SystemExit(0)
print("")
'
}

json_instance_public_url() {
  local port="$1"
  python3 -c '
import json, sys
target = str(sys.argv[1])
data = json.load(sys.stdin)
if isinstance(data, list) and data:
    data = data[0]

def first(*keys):
    if not isinstance(data, dict):
        return None
    for key in keys:
        value = data.get(key)
        if value not in (None, ""):
            return value
    return None

host = first("public_ipaddr", "public_ip", "ssh_host", "host", "ipaddr")
if isinstance(data, dict) and host:
    ports = data.get("ports")
    if isinstance(ports, dict):
        for key, mappings in ports.items():
            if str(key).startswith(target + "/") and isinstance(mappings, list):
                for mapping in mappings:
                    if isinstance(mapping, dict) and mapping.get("HostPort"):
                        print(f"http://{host}:{mapping.get('HostPort')}")
                        raise SystemExit(0)

def walk(obj):
    if isinstance(obj, dict):
        yield obj
        for value in obj.values():
            yield from walk(value)
    elif isinstance(obj, list):
        for value in obj:
            yield from walk(value)

candidate = None
for item in walk(data):
    text = " ".join(str(v) for v in item.values())
    if target in text:
        for key in ("HostPort", "host_port", "public_port", "external_port", "port"):
            value = item.get(key)
            if value and str(value) != target:
                candidate = str(value)
                break
    if candidate:
        break

for key, value in (data.items() if isinstance(data, dict) else []):
    if str(key) in (f"VAST_TCP_PORT_{target}", f"tcp{target}", f"port_{target}") and value:
        candidate = str(value)
        break

if host and candidate:
    print(f"http://{host}:{candidate}")
' "$port"
}

parse_and_print_offers() {
  python3 -c '
import json, sys
raw = sys.stdin.read()
data = json.loads(raw)
if isinstance(data, dict):
    for key in ("offers", "results", "data"):
        if isinstance(data.get(key), list):
            data = data[key]
            break
if not isinstance(data, list):
    raise SystemExit("Could not parse Vast offers JSON.")

print("IDX\tOFFER_ID\t$/HR\tGPU\tGPUS\tGPU_RAM_GB\tRELIABILITY\tLOCATION")
for idx, offer in enumerate(data[:10], 1):
    if not isinstance(offer, dict):
        continue
    offer_id = offer.get("id", "")
    price = offer.get("dph", offer.get("min_bid", ""))
    gpu = offer.get("gpu_name", offer.get("gpu_name_str", ""))
    gpus = offer.get("num_gpus", "")
    ram = offer.get("gpu_ram", offer.get("gpu_total_ram", ""))
    rel = offer.get("reliability", "")
    loc = offer.get("geolocation", offer.get("country", ""))
    print(f"{idx}\t{offer_id}\t{price}\t{gpu}\t{gpus}\t{ram}\t{rel}\t{loc}")
'
}

print_offers_table() {
  local offers_json="$1"
  if command -v column >/dev/null 2>&1; then
    printf '%s\n' "$offers_json" | parse_and_print_offers | column -t -s $'\t'
  else
    printf '%s\n' "$offers_json" | parse_and_print_offers
  fi
}

extract_offer_id_by_index() {
  local index="$1"
  python3 -c '
import json, sys
idx = int(sys.argv[1]) - 1
data = json.load(sys.stdin)
if isinstance(data, dict):
    for key in ("offers", "results", "data"):
        if isinstance(data.get(key), list):
            data = data[key]
            break
if not isinstance(data, list) or idx < 0 or idx >= len(data):
    raise SystemExit(1)
print(data[idx].get("id", ""))
' "$index"
}

shell_quote() {
  printf '%q' "$1"
}

build_search_query() {
  local query
  query="rentable=true cuda_vers>=${MIN_CUDA_VERSION} compute_cap>=${MIN_COMPUTE_CAP} direct_port_count>=1 num_gpus=${GPU_COUNT} gpu_ram>=${MIN_GPU_RAM} disk_space>=${DISK_GB}"
  if confirm_value "$VERIFIED_ONLY"; then
    query="${query} verified=true"
  fi
  if [[ -n "$MAX_PRICE" ]]; then
    query="${query} dph<=${MAX_PRICE}"
  fi
  printf '%s\n' "$query"
}

build_vllm_args_preview() {
  local q_model q_serving_key
  q_model="$(shell_quote "$MODEL_ID")"
  q_serving_key="$(shell_quote "$SERVING_API_KEY")"
  printf -- '--model %s --host 0.0.0.0 --port %s --api-key %s %s' "$q_model" "$DEFAULT_PORT" "$q_serving_key" "$EXTRA_VLLM_ARGS"
}

build_vllm_args_str() {
  printf -- '--model %s --host 0.0.0.0 --port %s --api-key %s %s' "$MODEL_ID" "$DEFAULT_PORT" "$SERVING_API_KEY" "$EXTRA_VLLM_ARGS"
}

build_vast_template_vllm_args() {
  printf -- '--max-model-len 8192 --gpu-memory-utilization 0.9 --generation-config vllm --download-dir /workspace/models --host 127.0.0.1 --port 18000 --api-key %s %s' "$SERVING_API_KEY" "$EXTRA_VLLM_ARGS"
}

is_default_vast_vllm_template() {
  [[ "$TEMPLATE_HASH" == "$DEFAULT_VAST_VLLM_TEMPLATE_HASH" ]]
}

create_instance_with_template() {
  local offer_id="$1"
  local payload output status http_status body

  if is_default_vast_vllm_template; then
    payload="$(python3 -c '
import json, sys
disk = float(sys.argv[1])
if disk.is_integer():
    disk = int(disk)
env = {
    "VLLM_MODEL": sys.argv[3],
    "VLLM_ARGS": sys.argv[4],
}
if sys.argv[5]:
    env["HF_TOKEN"] = sys.argv[5]
    env["HUGGING_FACE_HUB_TOKEN"] = sys.argv[5]
print(json.dumps({
    "client_id": "me",
    "disk": disk,
    "template_hash_id": sys.argv[2],
    "env": env,
    "force": False,
    "cancel_unavail": True,
}))
' "$DISK_GB" "$TEMPLATE_HASH" "$MODEL_ID" "$(build_vast_template_vllm_args)" "$HF_TOKEN")"
  else
    payload="$(python3 -c '
import json, sys
disk = float(sys.argv[1])
if disk.is_integer():
    disk = int(disk)
print(json.dumps({
    "client_id": "me",
    "disk": disk,
    "template_hash_id": sys.argv[2],
    "args_str": sys.argv[3],
    "force": False,
    "cancel_unavail": True,
}))
' "$DISK_GB" "$TEMPLATE_HASH" "$(build_vllm_args_str)")"
  fi

  set +e
  output="$(curl -sS -X PUT "https://console.vast.ai/api/v0/asks/${offer_id}/?api_key=${VAST_API_KEY}" \
    -H "Authorization: Bearer ${VAST_API_KEY}" \
    -H "Content-Type: application/json" \
    --data-binary "$payload" \
    -w $'\n%{http_code}' 2>&1)"
  status=$?
  set -e

  http_status="$(printf '%s\n' "$output" | tail -n 1)"
  body="$(printf '%s\n' "$output" | sed '$d')"

  if [[ "$status" -ne 0 || ! "$http_status" =~ ^2 ]]; then
    say ""
    say "${RED}Vast REST create instance failed (HTTP ${http_status:-unknown}):${RESET}" >&2
    printf '%s\n' "$body" | redact >&2
    exit 1
  fi

  printf '%s\n' "$body"
}

json_create_payload_preview() {
  if is_default_vast_vllm_template; then
    python3 -c '
import json, sys
print(json.dumps({
    "disk": sys.argv[1],
    "template_hash_id": sys.argv[2],
    "env": {
        "VLLM_MODEL": sys.argv[3],
        "VLLM_ARGS": sys.argv[4],
    },
}, separators=(",", ":")))
' "$DISK_GB" "$TEMPLATE_HASH" "$MODEL_ID" "$(build_vast_template_vllm_args)"
  else
    python3 -c '
import json, sys
print(json.dumps({
    "disk": sys.argv[1],
    "template_hash_id": sys.argv[2],
    "args_str": sys.argv[3],
}, separators=(",", ":")))
' "$DISK_GB" "$TEMPLATE_HASH" "$(build_vllm_args_str)"
  fi
}

build_onstart_cmd() {
  local q_model q_serving_key q_hf_token
  q_model="$(shell_quote "$MODEL_ID")"
  q_serving_key="$(shell_quote "$SERVING_API_KEY")"

  cat <<EOF
#!/usr/bin/env bash
set -Eeuo pipefail
mkdir -p /workspace/logs /workspace/.cache/huggingface
export HF_HOME=/workspace/.cache/huggingface
EOF

  if [[ -n "$HF_TOKEN" ]]; then
    q_hf_token="$(shell_quote "$HF_TOKEN")"
    cat <<EOF
export HF_TOKEN=${q_hf_token}
export HUGGING_FACE_HUB_TOKEN=${q_hf_token}
EOF
  fi

  cat <<EOF
echo "Starting vLLM for ${MODEL_ID} on port ${DEFAULT_PORT}" > /workspace/logs/vllm-launch.log
nohup vllm serve ${q_model} --host 0.0.0.0 --port ${DEFAULT_PORT} --api-key ${q_serving_key} ${EXTRA_VLLM_ARGS} >> /workspace/logs/vllm.log 2>&1 &
EOF
}

create_vast_template() {
  local template_name output status hash
  template_name="codex-vllm-${MODEL_ID//\//-}-$(date +%Y%m%d%H%M%S)"

  info "Creating private Vast template ${template_name}" >&2
  set +e
  output="$(vastai_cli create template \
    --name "$template_name" \
    --image "$DEFAULT_IMAGE" \
    --env "$ENV_OPTS" \
    --disk_space "$DISK_GB" \
    --desc "vLLM OpenAI-compatible server for ${MODEL_ID}" \
    --readme "OpenAI-compatible vLLM server on port ${DEFAULT_PORT}." \
    -n \
    2>&1)"
  status=$?
  set -e

  if [[ "$status" -ne 0 ]]; then
    say ""
    say "${RED}Vast template creation failed:${RESET}" >&2
    printf '%s\n' "$output" | redact >&2
    exit "$status"
  fi

  hash="$(printf '%s\n' "$output" | json_extract_template_hash 2>/dev/null || true)"
  if [[ -z "$hash" ]]; then
    say ""
    say "${RED}Could not parse template hash from Vast response:${RESET}" >&2
    printf '%s\n' "$output" | redact >&2
    exit 1
  fi

  printf '%s\n' "$hash"
}

redact() {
  sed -E 's/(sk-vast-)[a-f0-9]+/\1REDACTED/g; s/(hf_)[A-Za-z0-9_]+/\1REDACTED/g; s/([A-Za-z0-9_-]{30,})/REDACTED_SECRET/g'
}

wait_for_instance() {
  local instance_id="$1"
  local deadline=$((SECONDS + 1200))
  local raw status

  info "Waiting for instance ${instance_id} to reach running state" >&2
  while (( SECONDS < deadline )); do
    raw="$(vastai_cli show instance "$instance_id" --raw 2>/dev/null || true)"
    status="$(printf '%s' "$raw" | json_instance_status 2>/dev/null || true)"
    status="${status:-unknown}"

    case "$status" in
      running)
        ok "Instance is running." >&2
        printf '%s\n' "$raw"
        return 0
        ;;
      exited|offline|unknown)
        fail "Instance entered non-recoverable status: ${status}. Destroy it with: vastai destroy instance ${instance_id}"
        ;;
      *)
        printf '%b' "${DIM}.${RESET}" >&2
        sleep 15
        ;;
    esac
  done

  fail "Timed out waiting for instance ${instance_id}. Check it with: vastai show instance ${instance_id}"
}

wait_for_api() {
  local base_url="$1"
  local deadline=$((SECONDS + 900))
  local code

  info "Waiting for vLLM API health at ${base_url}/health"
  while (( SECONDS < deadline )); do
    code="$(curl -sS -o /dev/null -w '%{http_code}' --max-time 5 "${base_url}/health" 2>/dev/null || true)"
    if [[ "$code" == "200" || "$code" == "401" ]]; then
      ok "vLLM health endpoint is responding."
      return 0
    fi
    printf '%b' "${DIM}.${RESET}"
    sleep 10
  done

  warn "Timed out waiting for /health. The model may still be downloading or loading."
  return 1
}

wait_for_public_url() {
  local instance_id="$1"
  local deadline=$((SECONDS + 180))
  local raw url

  while (( SECONDS < deadline )); do
    raw="$(vastai_cli show instance "$instance_id" --raw 2>/dev/null || true)"
    url="$(printf '%s\n' "$raw" | json_instance_public_url "$DEFAULT_PORT" 2>/dev/null || true)"
    if [[ -n "$url" ]]; then
      printf '%s\n' "$url"
      return 0
    fi
    sleep 5
  done

  return 1
}

extract_proxy_token_from_logs() {
  local instance_id="$1"
  vastai_cli logs "$instance_id" 2>/dev/null | python3 -c '
import re, sys
text = sys.stdin.read()
patterns = (
    r"Authorization:\s*Bearer\s+([A-Za-z0-9_-]{32,})",
    r"password:\s*([A-Za-z0-9_-]{32,})",
    r"auth_token=([A-Za-z0-9_-]{32,})",
)
for pattern in patterns:
    match = re.search(pattern, text, re.IGNORECASE)
    if match:
        print(match.group(1))
        raise SystemExit(0)
raise SystemExit(1)
'
}

wait_for_proxy_token() {
  local instance_id="$1"
  local deadline=$((SECONDS + 300))
  local token

  while (( SECONDS < deadline )); do
    token="$(extract_proxy_token_from_logs "$instance_id" || true)"
    if [[ -n "$token" ]]; then
      printf '%s\n' "$token"
      return 0
    fi
    sleep 10
  done

  return 1
}

verify_models_endpoint() {
  local base_url="$1"
  local cookie_file status
  cookie_file="$(mktemp)"

  if [[ -n "${VAST_PROXY_TOKEN:-}" ]]; then
    curl -fsS --max-time 20 -c "$cookie_file" -u "${VAST_PROXY_USER}:${VAST_PROXY_TOKEN}" "${base_url}/health" >/dev/null 2>&1 || true
    status="$(curl -sS -o /dev/null -w '%{http_code}' --max-time 25 -b "$cookie_file" -H "Authorization: Bearer ${SERVING_API_KEY}" "${base_url}/v1/models" 2>/dev/null || true)"
  else
    status="$(curl -sS -o /dev/null -w '%{http_code}' --max-time 25 -H "Authorization: Bearer ${SERVING_API_KEY}" "${base_url}/v1/models" 2>/dev/null || true)"
  fi

  rm -f "$cookie_file"
  [[ "$status" == "200" ]]
}

write_summary() {
  local file="$1"
  umask 077
  {
    printf 'INSTANCE_ID=%q\n' "$INSTANCE_ID"
    printf 'MODEL_ID=%q\n' "$MODEL_ID"
    printf 'VLLM_BASE_URL=%q\n' "$PUBLIC_URL"
    printf 'VLLM_API_KEY=%q\n' "$SERVING_API_KEY"
    printf 'VAST_PROXY_USER=%q\n' "${VAST_PROXY_USER:-}"
    printf 'VAST_PROXY_TOKEN=%q\n' "${VAST_PROXY_TOKEN:-}"
    printf 'VAST_STOP_CMD=%q\n' "vastai stop instance ${INSTANCE_ID}"
    printf 'VAST_DESTROY_CMD=%q\n' "vastai destroy instance ${INSTANCE_ID}"
    printf 'VAST_LOGS_CMD=%q\n' "vastai logs ${INSTANCE_ID}"
  } >"$file"
}

print_usage() {
  say ""
  say "${BOLD}${GREEN}Deployment summary${RESET}"
  say "Instance ID: ${INSTANCE_ID}"
  say "Model:       ${MODEL_ID}"
  say "Base URL:    ${PUBLIC_URL:-"<pending: inspect Vast port mapping for internal port ${DEFAULT_PORT}>"}"
  say "API key:     ${SERVING_API_KEY}"
  if [[ -n "${VAST_PROXY_TOKEN:-}" ]]; then
    say "Proxy auth:  ${VAST_PROXY_USER}:<saved in ${SUMMARY_FILE}>"
  fi
  say "Logs:        vastai logs ${INSTANCE_ID}"
  say "Saved env:   ${SUMMARY_FILE}"
  say ""
  say "${BOLD}Use it with curl:${RESET}"
  if [[ -n "${VAST_PROXY_TOKEN:-}" ]]; then
    cat <<EOF
source ${SUMMARY_FILE}
COOKIE_FILE=\$(mktemp)

curl -fsS -c "\$COOKIE_FILE" -u "\${VAST_PROXY_USER}:\${VAST_PROXY_TOKEN}" \\
  ${PUBLIC_URL:-"http://PUBLIC_IP:PUBLIC_PORT"}/health >/dev/null

curl ${PUBLIC_URL:-"http://PUBLIC_IP:PUBLIC_PORT"}/v1/models \\
  -b "\$COOKIE_FILE" \\
  -H "Authorization: Bearer \${VLLM_API_KEY}"

curl ${PUBLIC_URL:-"http://PUBLIC_IP:PUBLIC_PORT"}/v1/chat/completions \\
  -b "\$COOKIE_FILE" \\
  -H "Authorization: Bearer \${VLLM_API_KEY}" \\
  -H "Content-Type: application/json" \\
  -d '{
    "model": "${MODEL_ID}",
    "messages": [{"role": "user", "content": "Write a one sentence deployment test."}],
    "max_tokens": 80
  }'
EOF
  else
    cat <<EOF
curl ${PUBLIC_URL:-"http://PUBLIC_IP:PUBLIC_PORT"}/v1/models \\
  -H "Authorization: Bearer ${SERVING_API_KEY}"

curl ${PUBLIC_URL:-"http://PUBLIC_IP:PUBLIC_PORT"}/v1/chat/completions \\
  -H "Authorization: Bearer ${SERVING_API_KEY}" \\
  -H "Content-Type: application/json" \\
  -d '{
    "model": "${MODEL_ID}",
    "messages": [{"role": "user", "content": "Write a one sentence deployment test."}],
    "max_tokens": 80
  }'
EOF
  fi
  say ""
  say "${BOLD}Use it with the OpenAI Python SDK:${RESET}"
  cat <<EOF
from openai import OpenAI

client = OpenAI(
    base_url="${PUBLIC_URL:-"http://PUBLIC_IP:PUBLIC_PORT"}/v1",
    api_key="${SERVING_API_KEY}",
)

response = client.chat.completions.create(
    model="${MODEL_ID}",
    messages=[{"role": "user", "content": "Hello from Vast.ai and vLLM."}],
    max_tokens=80,
)
print(response.choices[0].message.content)
EOF
  say ""
  say "${BOLD}Billing controls:${RESET}"
  say "Stop:    vastai stop instance ${INSTANCE_ID}"
  say "Destroy: vastai destroy instance ${INSTANCE_ID}"
}

main() {
  setup_colors
  load_dotenv
  VAST_API_KEY_INPUT="${VAST_API_KEY_INPUT:-${VAST_API_KEY:-${API_KEY:-}}}"
  HF_TOKEN="${HF_TOKEN:-}"
  parse_args "$@"
  require_python

  say "${BOLD}${MAGENTA}${APP_NAME}${RESET}"
  say "${DIM}Deploy a Hugging Face model on Vast.ai with vLLM and an OpenAI-compatible API.${RESET}"
  say ""

  prompt_if_empty VAST_API_KEY_INPUT "Vast.ai API key" "${VAST_API_KEY:-}" 1
  VAST_API_KEY="$VAST_API_KEY_INPUT"
  [[ -n "$VAST_API_KEY" ]] || fail "Vast.ai API key is required."

  prompt_if_empty MODEL_ID "Hugging Face model ID" ""
  [[ -n "$MODEL_ID" ]] || fail "Model ID is required."

  prompt_if_empty HF_TOKEN "Hugging Face token for gated/private models" "${HF_TOKEN:-}" 1
  prompt_if_empty GPU_COUNT "Number of GPUs" "$DEFAULT_GPU_COUNT"
  prompt_if_empty MIN_GPU_RAM "Minimum GPU RAM per GPU in GB" "$DEFAULT_MIN_GPU_RAM"
  prompt_if_empty MIN_CUDA_VERSION "Minimum CUDA version" "$DEFAULT_MIN_CUDA_VERSION"
  prompt_if_empty MIN_COMPUTE_CAP "Minimum CUDA compute capability x100" "$DEFAULT_MIN_COMPUTE_CAP"
  prompt_if_empty MAX_PRICE "Max hourly price in USD, blank for no cap" "$DEFAULT_MAX_PRICE"
  prompt_if_empty DISK_GB "Disk size in GB" "$DEFAULT_DISK"
  prompt_if_empty VERIFIED_ONLY "Verified machines only? y/n" "$DEFAULT_VERIFIED"
  prompt_if_empty PRICING_TYPE "Pricing type: on-demand or bid" "$DEFAULT_PRICING"
  prompt_if_empty EXTRA_VLLM_ARGS "Extra vLLM args, blank for none" ""

  VAST_API_KEY="$(trim "$VAST_API_KEY")"
  MODEL_ID="$(trim "$MODEL_ID")"
  GPU_COUNT="$(trim "$GPU_COUNT")"
  MIN_GPU_RAM="$(trim "$MIN_GPU_RAM")"
  MIN_CUDA_VERSION="$(trim "$MIN_CUDA_VERSION")"
  MIN_COMPUTE_CAP="$(trim "$MIN_COMPUTE_CAP")"
  MAX_PRICE="$(trim "$MAX_PRICE")"
  DISK_GB="$(trim "$DISK_GB")"
  VERIFIED_ONLY="$(normalize_bool "$VERIFIED_ONLY")"
  PRICING_TYPE="$(trim "$PRICING_TYPE")"
  EXTRA_VLLM_ARGS="$(trim "$EXTRA_VLLM_ARGS")"
  OFFER_INDEX="$(trim "$OFFER_INDEX")"
  TEMPLATE_HASH="$(trim "$TEMPLATE_HASH")"

  [[ "$PRICING_TYPE" == "on-demand" || "$PRICING_TYPE" == "bid" ]] || fail "--pricing must be on-demand or bid."
  [[ "$VERIFIED_ONLY" == "y" || "$VERIFIED_ONLY" == "n" ]] || fail "--verified must be y/n, true/false, or 1/0."

  SERVING_API_KEY="$(generate_key)"
  SEARCH_QUERY="$(build_search_query)"
  ORDER="dlperf_usd-"
  ENV_OPTS="-p ${DEFAULT_PORT}:${DEFAULT_PORT} -e OPEN_BUTTON_PORT=${DEFAULT_PORT} -e HF_HOME=/workspace/.cache/huggingface"
  if [[ -n "$HF_TOKEN" ]]; then
    ENV_OPTS="${ENV_OPTS} -e HF_TOKEN=${HF_TOKEN} -e HUGGING_FACE_HUB_TOKEN=${HF_TOKEN}"
  fi
  VLLM_ARGS=(--model "$MODEL_ID" --host "0.0.0.0" --port "$DEFAULT_PORT" --api-key "$SERVING_API_KEY")
  if [[ -n "$EXTRA_VLLM_ARGS" ]]; then
    read -r -a EXTRA_VLLM_ARGS_ARRAY <<< "$EXTRA_VLLM_ARGS"
    VLLM_ARGS+=("${EXTRA_VLLM_ARGS_ARRAY[@]}")
  fi

  ensure_vastai

  say ""
  info "Search query: ${SEARCH_QUERY}"

  info "Verifying Vast API key"
  set +e
  AUTH_OUTPUT="$(vastai_cli show user 2>&1)"
  AUTH_STATUS=$?
  set -e
  if [[ "$AUTH_STATUS" -ne 0 ]]; then
    say ""
    say "${RED}Vast authentication failed:${RESET}" >&2
    printf '%s\n' "$AUTH_OUTPUT" | redact >&2
    exit "$AUTH_STATUS"
  fi
  ok "Vast authentication verified."

  info "Searching GPU offers"
  set +e
  OFFERS_JSON="$(vastai_cli search offers "$SEARCH_QUERY" --raw --limit "$DEFAULT_OFFER_LIMIT" -o "$ORDER" -t "$PRICING_TYPE" 2>&1)"
  SEARCH_STATUS=$?
  set -e
  if [[ "$SEARCH_STATUS" -ne 0 ]]; then
    say ""
    say "${RED}Vast offer search failed:${RESET}" >&2
    printf '%s\n' "$OFFERS_JSON" | redact >&2
    exit "$SEARCH_STATUS"
  fi
  [[ -n "$OFFERS_JSON" ]] || fail "No offer data returned."

  say ""
  print_offers_table "$OFFERS_JSON"
  say ""

  if [[ "$DRY_RUN" == "1" ]]; then
    say "${BOLD}Dry-run create command shape:${RESET}"
    {
      printf 'vastai search offers %q --raw --limit %q -o %q -t %q\n' "$SEARCH_QUERY" "$DEFAULT_OFFER_LIMIT" "$ORDER" "$PRICING_TYPE"
      if [[ -n "$TEMPLATE_HASH" ]]; then
        printf 'curl -X PUT https://console.vast.ai/api/v0/asks/OFFER_ID/ --json %q\n' "$(json_create_payload_preview)"
      else
        printf 'vastai --raw create instance OFFER_ID --image %q --env %q --disk %q --args %s\n' "$DEFAULT_IMAGE" "$ENV_OPTS" "$DISK_GB" "$(build_vllm_args_preview)"
      fi
    } | redact
    say ""
    ok "Dry-run complete. No instance was created."
    exit 0
  fi

  prompt_if_empty OFFER_INDEX "Offer index to rent" "1"
  OFFER_INDEX="$(trim "$OFFER_INDEX")"
  OFFER_ID="$(printf '%s\n' "$OFFERS_JSON" | extract_offer_id_by_index "$OFFER_INDEX")"
  [[ -n "$OFFER_ID" ]] || fail "Could not resolve offer index ${OFFER_INDEX}."

  if [[ -n "$TEMPLATE_HASH" ]]; then
    ok "Using Vast template ${TEMPLATE_HASH}."
  else
    ok "Using direct image ${DEFAULT_IMAGE}."
  fi

  info "Creating Vast instance from offer ${OFFER_ID}"
  set +e
  if [[ -n "$TEMPLATE_HASH" ]]; then
    CREATE_JSON="$(create_instance_with_template "$OFFER_ID" 2>&1)"
  else
    CREATE_JSON="$(vastai_cli --raw create instance "$OFFER_ID" \
      --image "$DEFAULT_IMAGE" \
      --env "$ENV_OPTS" \
      --disk "$DISK_GB" \
      --args "${VLLM_ARGS[@]}" 2>&1)"
  fi
  CREATE_STATUS=$?
  set -e

  if [[ "$CREATE_STATUS" -ne 0 ]]; then
    say ""
    say "${RED}Vast create instance failed:${RESET}"
    printf '%s\n' "$CREATE_JSON" | redact >&2
    exit "$CREATE_STATUS"
  fi

  INSTANCE_ID="$(printf '%s\n' "$CREATE_JSON" | json_extract_new_contract 2>/dev/null || true)"
  if [[ -z "$INSTANCE_ID" ]]; then
    say ""
    say "${RED}Could not parse instance ID from Vast create response:${RESET}" >&2
    printf '%s\n' "$CREATE_JSON" | redact >&2
    exit 1
  fi
  ok "Created instance ${INSTANCE_ID}."

  INSTANCE_JSON="$(wait_for_instance "$INSTANCE_ID")"
  PUBLIC_URL="$(printf '%s\n' "$INSTANCE_JSON" | json_instance_public_url "$DEFAULT_PORT" 2>/dev/null || true)"
  if [[ -z "$PUBLIC_URL" ]]; then
    PUBLIC_URL="$(wait_for_public_url "$INSTANCE_ID" || true)"
  fi

  if [[ -n "$PUBLIC_URL" ]]; then
    wait_for_api "$PUBLIC_URL" || true
    VAST_PROXY_TOKEN=""
    if is_default_vast_vllm_template; then
      VAST_PROXY_TOKEN="$(wait_for_proxy_token "$INSTANCE_ID" || true)"
    fi
    verify_models_endpoint "$PUBLIC_URL" \
      && ok "/v1/models works with the generated API key." \
      || warn "/v1/models did not respond yet. Check logs with: vastai logs ${INSTANCE_ID}"
  else
    warn "Could not automatically discover the public URL for internal port ${DEFAULT_PORT}."
    warn "Use the Vast IP Port Info panel or inspect VAST_TCP_PORT_${DEFAULT_PORT} on the instance."
  fi

  SUMMARY_FILE="vast-vllm-${INSTANCE_ID}.env"
  write_summary "$SUMMARY_FILE"
  print_usage
}

if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
  main "$@"
fi

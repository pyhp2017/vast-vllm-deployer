# Vast vLLM Deployer

Interactive and CLI-friendly Bash deployer for running Hugging Face models on Vast.ai with vLLM and an OpenAI-compatible API.

The script searches Vast.ai GPU offers, rents the selected instance, launches a Vast-maintained vLLM template, creates a generated serving API key, waits for the endpoint, and writes a local `vast-vllm-INSTANCE.env` file with everything needed to call the model.

## Features

- Interactive prompts or fully non-interactive CLI flags
- Automatic Vast CLI installation into a local virtualenv
- `.env` support for `VAST_API_KEY`, `API_KEY`, and `HF_TOKEN`
- Offer filtering by GPU count, VRAM, CUDA version, compute capability, disk, price, and verified status
- Default Vast-maintained vLLM template using CUDA 12.8
- OpenAI-compatible `/v1/models`, `/v1/chat/completions`, and `/v1/completions`
- Saves generated API credentials locally with restrictive file permissions
- Dry-run mode that authenticates, searches offers, and prints the create request without renting

## Requirements

- macOS or Linux shell environment
- `bash`
- `python3`
- `curl`
- Vast.ai account and API key
- Optional: Hugging Face token for gated/private models

The script installs the `vastai` Python CLI into `.vastai-cli-venv` if `vastai` is not already available.

## Quick Start

```bash
git clone https://github.com/YOUR_USERNAME/vast-vllm-deployer.git
cd vast-vllm-deployer
chmod +x deploy-vllm-vast.sh
cp .env.example .env
```

Edit `.env`:

```bash
VAST_API_KEY=your_vast_api_key
HF_TOKEN=
```

Run a dry-run first:

```bash
./deploy-vllm-vast.sh --dry-run --yes \
  --model Qwen/Qwen3-8B \
  --gpus 1 \
  --min-gpu-ram 18 \
  --disk 120 \
  --no-verified \
  --max-price 0.25
```

Deploy:

```bash
./deploy-vllm-vast.sh --yes \
  --model Qwen/Qwen3-8B \
  --gpus 1 \
  --min-gpu-ram 18 \
  --disk 120 \
  --no-verified \
  --max-price 0.25 \
  --offer-index 1
```

When deployment finishes, the script writes a file like:

```text
vast-vllm-42971306.env
```

Source that file to use the API.

## Use the Model with curl

The default Vast vLLM template places a lightweight proxy in front of vLLM. Authenticate once with the proxy to get a cookie, then send the generated vLLM API key as a bearer token.

```bash
source vast-vllm-INSTANCE.env
COOKIE_FILE=$(mktemp)

curl -fsS -c "$COOKIE_FILE" -u "${VAST_PROXY_USER}:${VAST_PROXY_TOKEN}" \
  "$VLLM_BASE_URL/health" >/dev/null

curl "$VLLM_BASE_URL/v1/chat/completions" \
  -b "$COOKIE_FILE" \
  -H "Authorization: Bearer $VLLM_API_KEY" \
  -H "Content-Type: application/json" \
  -d '{
    "model": "Qwen/Qwen3-8B",
    "messages": [
      {"role": "user", "content": "Write a short hello message."}
    ],
    "max_tokens": 80,
    "temperature": 0.7
  }'
```

List models:

```bash
curl "$VLLM_BASE_URL/v1/models" \
  -b "$COOKIE_FILE" \
  -H "Authorization: Bearer $VLLM_API_KEY"
```

## Use with the OpenAI Python SDK

```python
from openai import OpenAI

client = OpenAI(
    base_url="http://PUBLIC_IP:PUBLIC_PORT/v1",
    api_key="sk-vast-...",
)

response = client.chat.completions.create(
    model="Qwen/Qwen3-8B",
    messages=[{"role": "user", "content": "Hello from Vast.ai and vLLM."}],
    max_tokens=80,
)

print(response.choices[0].message.content)
```

If your deployment uses the default Vast proxy, use the curl flow above or configure your HTTP client to first authenticate with the proxy and reuse its cookie.

## Common Options

```text
--dry-run                 Authenticate/search and show create payload without renting.
--yes, --non-interactive  Use defaults for missing optional values.
--vast-api-key KEY        Vast.ai API key. Can also use VAST_API_KEY or API_KEY.
--model MODEL_ID          Hugging Face model ID, for example Qwen/Qwen3-8B.
--hf-token TOKEN          Hugging Face token for gated/private models.
--gpus N                  Number of GPUs. Default: 1.
--min-gpu-ram GB          Minimum GPU RAM per GPU. Default: 16.
--min-cuda-version N      Minimum CUDA version. Default: 12.8.
--min-compute-cap N       Minimum CUDA compute capability x100. Default: 750.
--max-price USD_PER_HOUR  Max hourly price. Blank means no cap.
--disk GB                 Instance disk size. Default: 120.
--verified y|n            Filter to verified machines. Default: y.
--no-verified             Shortcut for --verified n.
--pricing on-demand|bid   Pricing type. Default: on-demand.
--extra-vllm-args ARGS    Extra args appended to vLLM.
--offer-index N           Offer table row to rent.
```

## Billing Controls

Vast instances keep billing while running. Destroy instances when finished:

```bash
source .env
.vastai-cli-venv/bin/vastai --api-key "$VAST_API_KEY" destroy instance INSTANCE_ID -y
```

The generated `vast-vllm-INSTANCE.env` file also includes a `VAST_DESTROY_CMD` value.

## Security Notes

- Do not commit `.env` or `vast-vllm-*.env` files.
- The generated vLLM API key protects the model endpoint.
- The default Vast template also exposes a proxy token; treat it as a secret.
- Rotate your Vast API key if it was ever committed or shared.

## License

MIT

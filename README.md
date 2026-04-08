---
title: Email Triage OpenEnv
colorFrom: blue
colorTo: blue
sdk: docker
app_port: 8000
pinned: false
---

# Email Triage OpenEnv

OpenEnv benchmark for customer-support ticket triage and resolution.

## Live Links

- GitHub: https://github.com/Prathamesh6607/master_meta_hackathon_new
- HF Space: https://huggingface.co/spaces/shiwangi82/master_meta_hackathon_new
- HF App URL: https://shiwangi82-master-meta-hackathon-new.hf.space

## Core Endpoints

- GET `/health`
- POST `/reset`
- POST `/reset/{task_id}`
- POST `/step/{task_id}`
- POST `/auto-step/{task_id}`
- POST `/pipeline/run`
- GET `/ui`

## Run Project On Port 8000

### Option 1: Docker (recommended)

```bash
git clone https://github.com/Prathamesh6607/master_meta_hackathon_new.git
cd master_meta_hackathon_new
docker build -t email-triage-env .
docker run --rm -p 8000:8000 email-triage-env
```

### Option 2: Native Python

```bash
python -m pip install -r requirements.txt
python -m uvicorn api.main:app --host 0.0.0.0 --port 8000
```

### Option 3: Windows PowerShell runner

```powershell
powershell -ExecutionPolicy Bypass -File .\server.ps1 -Port 8000
```

## UI Run And Check

Open UI in browser:

- http://127.0.0.1:8000/ui

Quick endpoint checks:

```bash
curl -X GET http://127.0.0.1:8000/health
curl -X POST http://127.0.0.1:8000/reset/task_1
curl -X POST http://127.0.0.1:8000/pipeline/run -H "Content-Type: application/json" -d '{"use_api":false}'
```

## Tasks

- `task_1`: classify support emails (category, priority, order ID)
- `task_2`: query policy and draft compliant response
- `task_3`: query order and inventory, then take final action

Pipeline flow: `task_1 -> task_2 -> task_3`

## Inference Script

`inference.py` is in project root.

Required environment variables:

- `API_BASE_URL` (default: `https://api.openai.com/v1`)
- `MODEL_NAME` (default: `gpt-4.1-mini`)
- `HF_TOKEN` (required)

Linux/macOS:

```bash
export API_BASE_URL="https://api.openai.com/v1"
export MODEL_NAME="gpt-4.1-mini"
export HF_TOKEN="hf_your_token"
python inference.py
```

Windows PowerShell:

```powershell
$env:API_BASE_URL = "https://api.openai.com/v1"
$env:MODEL_NAME = "gpt-4.1-mini"
$env:HF_TOKEN = "hf_your_token"
python inference.py
```

## HF Space Redeploy

```bash
huggingface-cli login
git remote add hf https://huggingface.co/spaces/shiwangi82/master_meta_hackathon_new
git push hf main
```

Re-verify:

```bash
curl -X GET https://shiwangi82-master-meta-hackathon-new.hf.space/health
curl -X POST https://shiwangi82-master-meta-hackathon-new.hf.space/reset/task_1
```

## Submission Files Checklist

- `openenv.yaml`
- `inference.py`
- `Dockerfile`
- `requirements.txt`

## Current Local Runtime Status

The project is running on port 8000 and UI is accessible at:

- http://127.0.0.1:8000/ui

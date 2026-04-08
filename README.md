---
title: Email Triage OpenEnv
emoji: "📨"
colorFrom: blue
colorTo: blue
sdk: docker
app_port: 8000
pinned: false
---

# Email Triage OpenEnv

**A Tier-2 Support Benchmark for Real-World AI Agent Workflows**

This is a production-ready OpenEnv environment that evaluates AI agents on realistic customer support tasks. The environment simulates actual support workflows where agents must triage incoming emails, apply business policies correctly, and resolve complex multi-step tickets using multiple system integrations.

### 🎯 Motivation

Real support work is multi-step, tool-dependent, and requires policy understanding. This benchmark tests whether agents can:
- **Classify** raw incoming emails with category, priority, and order ID extraction
- **Apply Policy** by querying the policy tool before drafting a response
- **Resolve Cases** using order DB and inventory lookups with correct decision logic

### ✅ OpenEnv Specification Compliance

This environment fully implements the OpenEnv interface:
- **Typed Models**: Pydantic-based `Observation`, `Action`, `Reward`, and `ToolTrace` models
- **Gym-like API**: `reset()` returns initial observation, `step(action)` returns (observation, reward, done, info)
- **Deterministic Grading**: Programmatic graders assign scores in [0.0, 1.0] range
- **Metadata**: Complete `openenv.yaml` with task definitions and observation/action spaces
- **Validation**: Passes `openenv validate` checks

## Tasks

Three tasks spanning increasing difficulty with deterministic graders:

| Task | Difficulty | Description | Max Steps | Grading Criteria |
|------|-----------|-------------|-----------|-----------------|
| `task_1` | **Easy** | Email triage: Classify emails with category, priority, and order ID extraction | 8 | 0.33 category + 0.33 priority + 0.34 order_id |
| `task_2` | **Medium** | Policy response: Query policy tool before drafting a policy-compliant response | 4 | 0.5 if policy queried + 0.5 correct policy outcome |
| `task_3` | **Hard** | Multi-system resolution: Order DB lookup → inventory check → final action (ship/refund) | 6 | 0.2 order query + 0.2 inventory query + 0.6 correct final action |

**Pipeline**: Tasks chain end-to-end (`task_1 → task_2 → task_3`) with automatic case handoff.

### Safety Rules

**Task 3** has hard-fail conditions that force score = 0.0:
- Issuing a refund when inventory is available
- Shipping a replacement for a non-existent order

## Action Space

Actions are JSON objects with an `action_type` field.

### Task 1 actions
- `{"action_type":"classify_email","category":"Shipping Delay","priority":"Normal","order_id":"ORD-1001"}`

### Task 2 actions
- `{"action_type":"query_policy","policy_question":"Can a 40-day-old order be returned?"}`
- `{"action_type":"draft_response","response_text":"...outside the 30-day window..."}`

### Task 3 actions
- `{"action_type":"query_order_db","order_id":"ORD-5001"}`
- `{"action_type":"query_inventory","sku":"SKU-BLEND-01"}`
- `{"action_type":"ship_replacement","order_id":"ORD-5001","reason":"defective_item"}`
- `{"action_type":"issue_refund","order_id":"ORD-5002","reason":"out_of_stock_replacement"}`

## Observation Space

Observations include:
- `task_id`, `step_number`
- `inbox` and `current_email` for `task_1`
- `ticket` for `task_2` and `task_3`
- `available_actions`
- `tool_traces` (tool call history)
- `context`, `last_action_error`

## Reward Function

**Deterministic and Reproducible**: All tasks score in [0.0, 1.0] with clear, programmatic grading:

- **task_1**: 0.33 (category correct) + 0.33 (priority correct) + 0.34 (order ID correct)
- **task_2**: 0.5 (if `query_policy` was called first) + 0.5 (if policy outcome is correct)
- **task_3**: 0.2 (order DB query) + 0.2 (inventory query) + 0.6 (correct final action)

**Incremental Feedback**: Reward is provided after each step, not just at episode end. Agents receive feedback on whether tool calls are appropriate, policy is respected, and decisions are sound.

**Baseline Scores**:

| Task | Deterministic Agent | Notes |
|------|-------------------|-------|
| `task_1` | 1.0 | All 4 emails classified correctly |
| `task_2` | 1.0 | Policy queried, response approved |
| `task_3` | 1.0 | Orders checked, inventory checked, correct decision |
| **Pipeline Average** | **1.0** | Full chained flow `task_1 → task_2 → task_3` |

## Setup

Python runtime target: **3.10.1**

```bash
pip install -r requirements.txt
uvicorn api.main:app --host 0.0.0.0 --port 8000
```

Then test the API:
```bash
curl -X POST http://localhost:8000/reset
```

## Baseline Inference Script

The environment includes `inference.py` (root directory) that demonstrates how to evaluate a model within the environment using the OpenAI client.

### Environment Variables

Your `inference.py` must read these environment variables:

| Variable | Description | Default | Required |
|----------|-----------|---------|----------|
| `API_BASE_URL` | LLM API endpoint | `https://api.openai.com/v1` | Optional (must have default) |
| `MODEL_NAME` | Model identifier for inference | `gpt-4.1-mini` | Optional (must have default) |
| `HF_TOKEN` | Hugging Face API token | — | **Mandatory** (no default) |

### Usage

```bash
export API_BASE_URL="https://api.openai.com/v1"
export MODEL_NAME="gpt-4.1-mini"
export HF_TOKEN="hf_your_token_here"

python inference.py
```

### Output Format

The inference script emits exactly three line types to stdout, in strict order:

**Format:**
```
[START] task=<task_name> env=<benchmark> model=<model_name>
[STEP]  step=<n> action=<action_str> reward=<0.00> done=<true|false> error=<msg|null>
[END]   success=<true|false> steps=<n> rewards=<r1,r2,...,rn>
```

**Rules:**
- One `[START]` line at episode begin
- One `[STEP]` line per step (immediately after `env.step()` returns)
- One `[END]` line after episode completion (even on error)
- `reward` and `rewards` formatted to 2 decimal places
- `done` and `success` are lowercase: `true` or `false`
- `error` is the raw error string or `null` if none
- All fields on a single line (no embedded newlines)

**Example Output:**
```
[START] task=task_1 env=email-triage-env model=gpt-4.1-mini
[STEP] step=1 action=classify_email category=Shipping\ Delay priority=Normal order_id=ORD-1001 reward=1.00 done=false error=null
[STEP] step=2 action=classify_email category=Product\ Defect priority=Urgent order_id=ORD-1002 reward=1.00 done=false error=null
[STEP] step=3 action=classify_email category=Billing\ Issue priority=Normal order_id=null reward=1.00 done=false error=null
[STEP] step=4 action=classify_email category=Account\ Access priority=Urgent order_id=ORD-1003 reward=1.00 done=true error=null
[END] success=true steps=4 rewards=1.00,1.00,1.00,1.00
```

### Implementation Example

```python
import os
import sys
from openai import OpenAI

# Read environment variables with defaults
API_BASE_URL = os.getenv("API_BASE_URL", "https://api.openai.com/v1")
MODEL_NAME = os.getenv("MODEL_NAME", "gpt-4.1-mini")
HF_TOKEN = os.getenv("HF_TOKEN")

# HF_TOKEN is mandatory
if HF_TOKEN is None:
    raise ValueError("HF_TOKEN environment variable is required")

# Initialize OpenAI client
client = OpenAI(
    base_url=API_BASE_URL,
    api_key=HF_TOKEN
)

def run_task(task_id: str):
    """Execute a single task with the environment."""
    # TODO: Reset environment, run steps, emit output in required format
    pass

if __name__ == "__main__":
    for task_id in ['task_1', 'task_2', 'task_3']:
        run_task(task_id)
```

## Containerized Execution & Deployment

### Local Docker Validation

**Dockerfile** is production-ready for Hugging Face Spaces:

```bash
docker build -t email-triage-env .
docker run -p 8000:8000 email-triage-env
```

Verify:
```bash
curl -X POST http://localhost:8000/reset
```

### Hugging Face Space Deployment

**Requirements for Submission:**

1. **Space Configuration**
   - Space name: `email-triage-env` (or your variant)
   - Tags: `openenv`
   - Hardware: CPU (2 vCPU, 8 GB RAM)

2. **Before Submitting:**
   - Ensure your Space is fully **built** (not building)
   - Confirm Space is in **"Running"** state
   - Turn off other active Spaces to avoid build delays
   - Test endpoint: `POST https://your-space/reset`

3. **Set Environment Variables** (in Space settings):
   ```
   API_BASE_URL = https://api.openai.com/v1
   MODEL_NAME = gpt-4.1-mini
   HF_TOKEN = <your-token>
   ```

4. **Push to Space:**
   ```bash
   huggingface-cli login
   huggingface-cli repo create email-triage-env --type space --space-sdk docker
   git clone https://huggingface.co/spaces/<your-username>/email-triage-env
   cd email-triage-env
   # Copy your repo files here
   git add .
   git commit -m "Initial commit"
   git push
   ```

5. **Verify After Deploy:**
   ```bash
   curl -X POST https://<your-username>-email-triage-env.hf.space/reset
   ```

### Local Docker with Docker Compose

For parity testing before Space deployment:

```bash
docker compose -f docker-compose.deploy.yml up --build
```

Then visit:
- API: `http://127.0.0.1:8000/`
- UI: `http://127.0.0.1:8000/ui`

## Hardware Requirements

Your solution must run within the following constraints:

| Requirement | Value |
|-------------|-------|
| vCPU | 2 |
| RAM | 8 GB |
| Disk | Varies (model-dependent) |

**Key Points:**
- Ensure your model, dependencies, and runtime fit within these limits
- Large language models may exceed these constraints
- Submissions exceeding constraints may fail during evaluation
- Test locally first to verify resource usage

## Hackathon Submission Checklist

✅ **Project Structure**
- `inference.py` is in the root directory
- `Dockerfile` is present and working
- `requirements.txt` lists all dependencies
- `openenv.yaml` is complete

✅ **LLM Usage**
- `inference.py` uses `OpenAI` client from the `openai` package
- No alternative SDKs or direct HTTP calls

✅ **Environment Variables**
- `API_BASE_URL` - has default value ✓
- `MODEL_NAME` - has default value ✓
- `HF_TOKEN` - mandatory, no default ✓

✅ **Inference Output Format**
- Emits `[START]`, `[STEP]`, `[END]` lines in correct format
- Rewards formatted to 2 decimal places
- Done/success are lowercase booleans

✅ **Hugging Face Space**
- Space is set to **Running** state before submission
- All other Spaces are turned off
- Environment variables configured in Space settings

✅ **Hardware Requirements**
- Solution runs within 2 vCPU, 8 GB RAM
- Docker image builds successfully
- Model/dependencies fit within constraints

✅ **Documentation**
- README includes environment overview ✓
- Action/observation spaces defined ✓
- Task descriptions with difficulty levels ✓
- Baseline scores documented ✓
- Setup instructions included ✓

## Round 1 Submission Pack (Hackathon-Ready)

### 1) Environment Summary

- Environment name: `email-triage-env`
- Domain: customer support workflow automation
- Tasks: `task_1`, `task_2`, `task_3`
- API style: Gym-like reset/step over HTTP
- Deterministic grading: yes (see reward logic below)

### 2) Observation, Action, Reward, Done

Observation fields:
- `task_id`, `step_number`
- `inbox`, `current_email` (`task_1`)
- `ticket` (`task_2`, `task_3`)
- `available_actions`, `tool_traces`, `context`, `last_action_error`

Action space:
- `task_1`: `classify_email`
- `task_2`: `query_policy`, `draft_response`
- `task_3`: `query_order_db`, `query_inventory`, `ship_replacement`, `issue_refund`

Reward function (range `[0.0, 1.0]`):
- `task_1`: `0.33 category + 0.33 priority + 0.34 order_id`
- `task_2`: `0.5` if policy queried before response + `0.5` policy-correct outcome
- `task_3`: `0.2` order query + `0.2` inventory query + `0.6` correct final action

Done conditions:
- Episode ends when `max_steps` is reached, or early when task logic is complete.
- `task_2` and `task_3` terminate on final decision action.

### 3) Hard Fail Safety Rules (Task 3)

Immediate zero score if:
- refund is issued while inventory is available
- replacement is shipped for a non-existent order

### 4) Core API Endpoints

| Endpoint | Method | Purpose |
|----------|--------|---------|
| `/reset` | POST | Reset any task (defaults to `task_1`) - returns `{"observation": {...}}` |
| `/reset/{task_id}` | POST | Reset specific task - returns `{"observation": {...}}` |
| `/step/{task_id}` | POST | Execute action in task - returns observation, reward, done, info |
| `/auto-step/{task_id}` | POST | Auto-choose action (with optional LLM assist) |
| `/pipeline/run` | POST | Run full chained pipeline: `task_1 → task_2 → task_3` |
| `/health` | GET | Health check - returns `{"status": "ok", "environment": "email-triage-env", "tasks": [...]}` |

### 5) Quick Evaluator Test

### 6) Chained Task Flow (Pipeline)

The environment supports chained end-to-end evaluation:

**Flow:** `task_1` → (handoff) → `task_2` → (handoff) → `task_3`

1. **task_1** (Email Triage): Classify emails, extract order IDs
   - Best classification becomes a return-policy ticket
2. **task_2** (Policy Response): Query policy, draft response
   - Policy decision becomes context for defective-item resolution
3. **task_3** (Multi-System Resolution): Order DB + inventory checks
   - Final action: ship replacement or issue refund

**Run via API:**
```bash
curl -X POST http://localhost:8000/pipeline/run \
  -H "Content-Type: application/json" \
  -d '{"use_api": false}'
```

**Response Structure:**
```json
{
  "use_api": false,
  "pipeline_order": ["task_1", "task_2", "task_3"],
  "average_score": 1.0,
  "handoff": {
    "task1_to_task2": {...synthesized task_2 case...},
    "task2_to_task3": {...synthesized task_3 case...}
  },
  "results": {
      "task_1": {"score": 1.0, "steps": 4, "done": true, "trace": [...]},
    "task_2": {"score": 1.0, "steps": 2, "done": true, "trace": [...]},
    "task_3": {"score": 1.0, "steps": 3, "done": true, "trace": [...]}
  }
}
```

### 7) Sample Episode Traces

**task_1 (Email Triage) - Expected Good Behavior:**
```
POST /reset/task_1
→ observation: {task_id: "task_1", inbox: [4 emails], current_email: {...}, available_actions: ["classify_email"]}

POST /step/task_1
body: {"action_type": "classify_email", "category": "Shipping Delay", "priority": "Normal", "order_id": "ORD-1001"}
→ reward: 1.0, observation: {current_email: next_email}

... repeat for 4 emails ...

POST /step/task_1
→ reward: 1.0, done: true
```

**task_2 (Policy Response) - Expected Good Behavior:**
```
POST /reset/task_2
→ observation: {task_id: "task_2", ticket: {subject: "Return request", message: "...30 days since delivery"}, available_actions: ["query_policy", "draft_response"]}

POST /step/task_2
body: {"action_type": "query_policy", "policy_question": "Can this 30-day-old order be returned?"}
→ reward: 0.5, observation: {policy_result: {window_days: 30}, available_actions: ["draft_response"]}

POST /step/task_2
body: {"action_type": "draft_response", "response_text": "Thanks for contacting us. Your return is approved under our 30-day policy..."}
→ reward: 0.5, done: true (total: 1.0)
```

**task_3 (Multi-System Resolution) - Expected Good Behavior:**
```
POST /reset/task_3
→ observation: {task_id: "task_3", ticket: {reported_order_id: "ORD-5001"}, available_actions: ["query_order_db", "query_inventory", "ship_replacement", "issue_refund"]}

POST /step/task_3
body: {"action_type": "query_order_db", "order_id": "ORD-5001"}
→ reward: 0.2, observation: {order_result: {order_exists: true, sku: "SKU-BLEND-01"}, available_actions: ["query_inventory", ...]}

POST /step/task_3
body: {"action_type": "query_inventory", "sku": "SKU-BLEND-01"}
→ reward: 0.2, observation: {inventory_result: {in_stock: 2}, available_actions: ["ship_replacement", "issue_refund"]}

POST /step/task_3
body: {"action_type": "ship_replacement", "order_id": "ORD-5001", "reason": "defective_item"}
→ reward: 0.6, done: true (total: 1.0)
```

### 8) Submission & Resubmission

**Submission Requirements:**
- ✅ `inference.py` in root directory
- ✅ Hugging Face Space running and accessible
- ✅ Space returns valid responses to `POST /reset`
- ✅ Environment variables set in Space settings
- ✅ All dependencies in `requirements.txt`

**If Submission Fails:**
1. Check error message in submission logs
2. Fix the issue(s) locally
3. Rebuild Docker image: `docker build -t email-triage-env .`
4. Test locally: `docker run -p 8000:8000 email-triage-env`
5. Push fixes to Space repo
6. Wait for Space to rebuild and enter "Running" state
7. **Resubmit** (no penalty for resubmissions)

**Common Failure Cases to Avoid:**
- ❌ `inference.py` not in root directory → move it
- ❌ Missing default values for `API_BASE_URL` or `MODEL_NAME` → add defaults
- ❌ Missing `HF_TOKEN` validation → add check
- ❌ Hugging Face Space still building → wait for build to complete
- ❌ Multiple active Spaces → turn off others (build resource contention)
- ❌ Space in "Stopped" state → restart or redeploy
- ❌ Port hardcoded to non-8000 value → use port 8000
- ❌ Inference output not in `[START]`/`[STEP]`/`[END]` format → check output format
- ❌ Rewards not formatted to 2 decimal places → use `f"{reward:.2f}"`

## UI Frontend (Interactive Demo)

This project now includes a browser UI to demo how the environment works step-by-step, with a Meta-blue theme and a corpus-backed support search.

- URL: `http://127.0.0.1:8000/ui`
- Features:
	- Task selector (`task_1`, `task_2`, `task_3`)
	- Optional Hugging Face Space + ML assistance toggle for auto-step
	- Manual action builder and submit
	- Auto Next and full Run Episode
	- Run Full Pipeline (`task_1 -> task_2 -> task_3`) with explicit handoff
	- Live metrics + timeline
	- Human-readable observation and final task response panels
	- Corpus-backed support recommendations from the local dataset index
	- Browser support search panel for querying the corpus directly
	- Corpus stats card showing records and top labels
	- Meta-blue visual theme for pitch/demo use

When **Hugging Face Space + ML assistance** is enabled (checkbox in UI or `use_api=true` in API):
- `task_1` attempts external email classification via HF Space, falls back to deterministic heuristic if unavailable
- `task_2` attempts external response generation, validates against policy, falls back to safe template
- `task_3` uses deterministic order/inventory logic (no external calls)
- Full pipeline runs end-to-end even if external service is unavailable

**Verified live behavior:**
- Task_1: 4 emails triaged correctly (score 1.0)
- Task_2: Policy query + approved response (score 1.0)
- Task_3: Order lookup + inventory check + ship replacement (score 1.0)
- **All three tasks chained with deterministic actions: average score 1.0**

HF Space integration is also supported for API-assisted behavior in auto-step:
- Space URL: `https://gayathrisoorya-email-classification-new.hf.space`
- Space repo id: `gayathrisoorya/email_classification_new`
- Set `HF_EMAIL_CLASSIFIER_SPACE_URL` in your environment to override target Space.

When `POST /auto-step/{task_id}` is called with `use_api=true`:
- `task_1` first attempts external email classification via the HF Space API.
- `task_2` attempts external response generation, then validates policy correctness.
- If the Space is unavailable or output is malformed, the backend falls back to deterministic logic.

The backend builds an inverted index over the local support corpus in `datasets/` and returns retrieval-backed support recommendations for each step. This makes the demo more explainable by showing corpus-grounded support triage instead of a pure black-box reply.

## Project Structure

```
email-triage-env/
├── api/                          # FastAPI application
│   └── main.py                   # HTTP endpoints
├── env/                          # Environment core
│   ├── environment.py            # OpenEnv interface
│   ├── models.py                 # Pydantic models
│   ├── graders.py                # Task graders
│   ├── rl_agent.py              # Task 1 agent
│   ├── tasks.py                 # Task definitions
│   ├── support_kb.py            # Corpus search
│   └── data_generator.py        # Case generation
├── ui/                          # Browser UI
│   ├── index.html
│   ├── app.js
│   └── styles.css
├── datasets/                    # Support corpus & logs
│   ├── meta_support_subset.csv
│   ├── epoch_training_log.jsonl
│   └── task1_agent_policy.json
├── scripts/                     # Utilities
│   ├── build_meta_support_subset.py
│   └── generate_ui_diagrams.py
├── data/                        # Task template datasets
│   ├── task1_dataset.template.json
│   ├── task2_dataset.template.json
│   └── task3_dataset.template.json
├── inference.py                 # **Baseline inference script (required)**
├── Dockerfile                   # Container specification
├── docker-compose.deploy.yml    # Local Docker Compose
├── requirements.txt             # Python dependencies
├── openenv.yaml                 # OpenEnv metadata
└── README.md                    # This file
```

## Quick Start (Local Development)

### Prerequisites
- Python 3.10.1
- Docker (for containerized testing)

### Setup & Run Locally

```bash
# Clone and navigate to the repository
cd email-triage-env

# Create virtual environment
python -m venv .venv
source .venv/bin/activate  # On Windows: .\.venv\Scripts\activate

# Install dependencies
pip install -r requirements.txt

# Start the API
uvicorn api.main:app --host 0.0.0.0 --port 8000
```

Visit:
- **API Health**: http://localhost:8000/health
- **UI Demo**: http://localhost:8000/ui
- **API Reset Endpoint**: `curl -X POST http://localhost:8000/reset`

### Run Baseline Inference

```bash
export API_BASE_URL="https://api.openai.com/v1"
export MODEL_NAME="gpt-4.1-mini"
export HF_TOKEN="your-hf-token"
python inference.py
```

### Docker Local Testing

```bash
docker build -t email-triage-env .
docker run -p 8000:8000 \
  -e API_BASE_URL="https://api.openai.com/v1" \
  -e MODEL_NAME="gpt-4.1-mini" \
  -e HF_TOKEN="your-hf-token" \
  email-triage-env
```

## Additional Resources

### POC Demo

See [POC.md](POC.md) for the current demo flow and pitch script.

## Regenerate UI Diagrams

The flow and feature diagrams shown in the UI are generated with Python
`matplotlib` and exported as SVG assets.

```powershell
& ".\.venv\Scripts\python.exe" -m pip install matplotlib
& ".\.venv\Scripts\python.exe" "scripts\generate_ui_diagrams.py"
```

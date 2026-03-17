# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

**g-vllm-exp** is a CPU-focused vLLM experimentation setup for running LLM inference on AMD EPYC and smaller remote VMs. It provides:
- A build and launch system for vLLM CPU backend
- OpenAI-compatible API server on port 8000
- Interactive test client with streaming and metrics
- Concurrent benchmarking script comparing vLLM vs Ollama
- Hardware inspection and tuning documentation

**Key Technologies:** Python 3.12+, `uv`, vLLM (CPU backend), OpenAI SDK, bash scripts

## High-Level Architecture

### Core Components

1. **setup.sh** — System dependency installation and vLLM source build
   - Installs Python build tools, OpenMP, TCMalloc, etc.
   - Clones and builds the vllm/ source with `VLLM_TARGET_DEVICE=cpu`
   - Sets up `.venv` for reproducible Python environment

2. **start_vllm_cpu.sh** — Server lifecycle launcher
   - Validates environment (venv exists, libiomp loaded, RAM available)
   - Exports LD_PRELOAD for Intel OpenMP and optional TCMalloc
   - Runs `vllm serve` with CPU-tuned defaults (Qwen/Qwen3-4B, 8 threads, 16GB KV cache, max context 32768)
   - Conditionally enables NUMA binding if multiple nodes detected

3. **benchmark.py** — Concurrent vLLM vs Ollama comparison
   - **Server Lifecycle Management:** Pre-flight process cleanup (`_kill_existing_vllm()`, `_kill_existing_ollama()`), start, health check, stop
   - **Concurrent Load Testing:** Sends [1, 5, 10] concurrent requests per prompt; tracks latency, TTFT, p95, throughput
   - **Results Aggregation:** JSON output with per-server and per-concurrency metrics
   - Full lifecycle: vLLM (start → benchmark → stop) → sleep 3s → Ollama (start → benchmark → stop)

4. **test_vllm_api.py** — Interactive and one-shot client
   - Uses OpenAI SDK to stream responses from port 8000
   - Tracks TTFT, latency, and per-phase token throughput (prompt, decode)
   - Supports interactive mode (REPL) and one-shot mode

### Process Lifecycle Pattern

Both benchmark.py and start_vllm_cpu.sh follow a consistent pattern:

```
Pre-flight cleanup (kill stray process on port)
    ↓
Start subprocess (Popen with start_new_session=True)
    ↓
Health check (poll endpoint until ready or timeout)
    ↓
Use (send requests, benchmark)
    ↓
Stop (SIGTERM → 15s wait → SIGKILL if needed)
```

Key consideration: **Pre-flight cleanup is critical.** If a previous run left a server bound to the port and the new `Popen` fails silently on conflict, `wait_for_server()` will succeed against the orphaned process and `stop()` will kill a dead PID, leaving the orphan running.

## Common Development Commands

### Setup and Server Startup
```bash
./setup.sh                      # Install dependencies and build vLLM from source
chmod +x start_vllm_cpu.sh      # (if needed)
./start_vllm_cpu.sh             # Start vLLM on port 8000
```

### Testing and Interaction
```bash
uv run test_vllm_api.py                                    # Interactive mode (REPL)
uv run test_vllm_api.py "What is the capital of France?"  # One-shot prompt
uv run test_vllm_api.py "Explain NUMA briefly" --max-tokens 150
```

### Benchmarking
```bash
uv run benchmark.py               # Full vLLM + Ollama lifecycle and comparison
uv run benchmark.py --vllm-only   # Skip to vLLM benchmark (server must already be running)
uv run benchmark.py --ollama-only # Skip to Ollama benchmark (server must already be running)
```

### Validation Before Committing
```bash
bash -n setup.sh && bash -n start_vllm_cpu.sh  # Syntax check shell scripts
python3 -m py_compile test_vllm_api.py benchmark.py  # Syntax check Python
git status --short                             # Check modified/untracked files
git log --since='4 hours ago' --oneline        # Review recent commits
```

## Key Configuration

**Ports and Endpoints:**
- vLLM: `http://localhost:8000/v1` (OpenAI-compatible), health: `/health`
- Ollama: `http://localhost:11434/v1` (OpenAI-compatible), health: `/api/version`

**Defaults in start_vllm_cpu.sh** (tuned for 8-core AMD EPYC):
- Model: `Qwen/Qwen3-4B`
- Max context length: 32768 tokens
- CPU threads: 8 (DEFAULT_THREADS)
- KV cache: 16 GiB (DEFAULT_KV_CACHE_GIB)
- Min available RAM: 12 GiB

**Defaults in benchmark.py:**
- vLLM model name (served as): `qwen-local`
- Ollama model: `qwen3:4b`
- Concurrency levels: [1, 5, 10]
- Max output tokens per request: 200
- Server startup timeout: 300s
- Test prompts: short (2+2), medium (CPU explanation), long (AI history)

## Important Patterns & Considerations

### Process Cleanup and Port Management
- **_kill_existing_vllm():** Uses `fuser -n tcp 8000` to find and SIGTERM any process on port 8000
- **_kill_existing_ollama():** Uses `pgrep -x ollama` to find and SIGTERM the binary by name
- Both wait 2s after killing to allow the OS to free the port
- This prevents the silent-failure pattern where a new server's `Popen` fails but the health check passes against an orphaned old server

### Server Startup and Health Checks
- `start_vllm()` returns a `Popen` object; the real PID is passed to `wait_for_server()` and `stop_vllm()`
- `wait_for_server()` polls the health endpoint every 1-2s until ready or timeout (300s)
- Process groups (`os.getpgid()`, `os.killpg()`) ensure child processes are cleaned up alongside the parent

### Async Concurrent Requests in benchmark.py
- Uses `httpx.AsyncClient` to send concurrent requests to `/v1/chat/completions`
- Measures TTFT by capturing the timestamp of the first chunk in the response stream
- Aggregates per-request latencies into min/p50/p95/max statistics
- Results are JSON-serialized to `benchmark_results.json` for later analysis

### vllm/ Subdirectory
- The `vllm/` directory is a local checkout of the upstream vLLM source repo
- Treat it as vendored code unless intentionally modifying upstream internals
- `setup.sh` builds from this local copy with `uv pip install . --no-build-isolation`

## Testing and Validation

### Smoke Test Flow
1. Run `./setup.sh` and verify no errors
2. Run `./start_vllm_cpu.sh` and let it start (takes ~30-60s for first model load)
3. In another terminal, run `uv run test_vllm_api.py "test prompt"` and confirm streaming output and metrics
4. Stop the server with Ctrl+C
5. Optionally run `uv run benchmark.py --vllm-only` to test the async client

### Changes to Launcher (start_vllm_cpu.sh)
- Verify syntax with `bash -n start_vllm_cpu.sh`
- Test startup on the actual hardware (port 8000 must be free)
- Confirm server is ready: `curl http://localhost:8000/health`
- Run a quick test prompt: `uv run test_vllm_api.py "test"`

### Changes to benchmark.py or test_vllm_api.py
- Syntax check: `python3 -m py_compile <file>`
- Run the affected test script (e.g., `uv run test_vllm_api.py` or `uv run benchmark.py --vllm-only`)
- Check output for expected metrics and no exceptions

## Recent Context

- **Pre-flight cleanup:** `_kill_existing_vllm()` and `_kill_existing_ollama()` added to benchmark.py to prevent orphaned servers when running consecutive benchmarks
- **Model tuning:** Default model changed to Qwen/Qwen3-4B with 8 threads and 16GB KV cache for 8-core AMD EPYC
- **Concurrent benchmarking:** benchmark.py added with full lifecycle management and comparative vLLM vs Ollama metrics
- **Interactive client:** test_vllm_api.py supports both REPL and one-shot modes with detailed performance metrics

## Commit Guidelines

Follow the existing imperative style with prefixes:
- `feat:` for new features
- `fix:` for bug fixes
- `refactor:` for code restructuring
- `docs:` for documentation updates

Examples:
- `feat: add concurrent benchmark for vLLM vs Ollama`
- `fix: add pre-flight kill for vLLM and Ollama before starting servers`

Include in PR/commit:
- Short summary of user-visible change
- Any setup or runtime impact
- Verification commands and output (especially for launcher changes)

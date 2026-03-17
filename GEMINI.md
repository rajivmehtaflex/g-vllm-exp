# GEMINI.md - Project Context

## Project Overview
`g-vllm-exp` is a CPU-focused experimental wrapper for **vLLM**, optimized for running inference on hardware like AMD EPYC processors as well as smaller remote VMs. It is managed using `uv` and provides scripts for environment setup, server management, and interactive testing. The current default model is `Qwen/Qwen3-1.7B`.

- **Main Technologies:** Python (>= 3.12), `uv`, `vLLM` (CPU backend), `OpenAI SDK`.
- **Key Files:**
  - `AGENTS.md`: Repository guidelines, structure, and conventions document.
  - `main.py`: Basic entry point script for the project.
  - `setup.sh`: System package installation and vLLM build script.
  - `start_vllm_cpu.sh`: Launches the OpenAI-compatible vLLM server with CPU optimizations (NUMA, TCMalloc, OpenMP).
  - `test_vllm_api.py`: Feature-rich client for interacting with the local server.
  - `check_hw.sh`: Hardware inspection script (CPU/NUMA).
  - `vllm/`: Local checkout of the vLLM source code.

## Building and Running

### Prerequisites
- [uv](https://github.com/astral-sh/uv) installed.
- Ubuntu 24.04 (recommended environment).

### Setup and Start
1.  **Initialize Environment:**
    ```bash
    chmod +x setup.sh && ./setup.sh
    ```
2.  **Start Inference Server:**
    ```bash
    chmod +x start_vllm_cpu.sh && ./start_vllm_cpu.sh
    ```

### Testing and Interaction
The `test_vllm_api.py` script supports interactive and one-shot modes:
- **Interactive Mode:**
  ```bash
  uv run test_vllm_api.py
  ```
- **One-shot Prompt:**
  ```bash
  uv run test_vllm_api.py "Explain quantum computing in 2 sentences."
  ```
- **Key Features:** Streaming output, Time-to-First-Token (TTFT) tracking, token counts, and throughput metrics (tok/s).

## Recent Updates
- **Repository Guidelines:** Added `AGENTS.md` for detailed project structure, testing, and PR conventions.
- **Default Model Shift:** Switched to `Qwen/Qwen3-1.7B` as the baseline default model, configured to run with reasoning mode disabled by default.
- **Project Structure:** Added `main.py` entry point.
- **Interactive CLI:** Added `argparse` and a REPL-style loop to `test_vllm_api.py` for continuous testing.
- **Streaming & Metrics:** Implemented streaming responses with real-time token display and detailed performance metrics (latency, TTFT, throughput).
- **CPU Optimization Docs:** Updated `README.md` to document specific issues and fixes for running vLLM on remote CPU-only VMs.

## Development Conventions
- **Language:** Python 3.12+.
- **Shell Scripts:** Use `bash` with `set -euo pipefail`.
- **Tooling:** Always use `uv` for dependency and environment management.
- **Style & PRs:** Refer to `AGENTS.md` for in-depth coding style, branch workflows, and PR requirements.
- **Testing:** Validate changes by running syntax checks (`py_compile`, `bash -n`) and smoke-testing with `test_vllm_api.py` as outlined in `AGENTS.md`.

# GEMINI.md - Project Context

## Project Overview
`g-vllm-exp` is a CPU-focused experimental wrapper for **vLLM**, optimized for running inference on hardware like AMD EPYC processors. It is managed using `uv` and provides scripts for environment setup, server management, and interactive testing.

- **Main Technologies:** Python (>= 3.12), `uv`, `vLLM` (CPU backend), `OpenAI SDK`.
- **Key Files:**
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
The `test_vllm_api.py` script (updated Mar 16, 2026) supports interactive and one-shot modes:
- **Interactive Mode:**
  ```bash
  uv run test_vllm_api.py
  ```
- **One-shot Prompt:**
  ```bash
  uv run test_vllm_api.py "Explain quantum computing in 2 sentences."
  ```
- **Key Features:** Streaming output, Time-to-First-Token (TTFT) tracking, token counts, and throughput metrics (tok/s).

## Recent Updates (March 16, 2026)
- **Interactive CLI:** Added `argparse` and a REPL-style loop to `test_vllm_api.py` for continuous testing.
- **Streaming & Metrics:** Implemented streaming responses with real-time token display and detailed performance metrics (latency, TTFT, throughput).
- **CPU Optimization Docs:** Updated `README.md` to document specific issues and fixes for running vLLM on remote CPU-only VMs.

## Development Conventions
- **Language:** Python 3.12+.
- **Shell Scripts:** Use `bash` with `set -euo pipefail`.
- **Tooling:** Always use `uv` for dependency and environment management.
- **Style:** Adhere to PEP 8; use descriptive snake_case for Python symbols.
- **Testing:** Validate changes by running syntax checks (`py_compile`, `bash -n`) and smoke-testing with `test_vllm_api.py`.

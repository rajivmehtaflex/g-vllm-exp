# vLLM CPU Experiment

This project contains a CPU-only **vLLM** setup for Ubuntu 24.04. It started as an EPYC-oriented configuration, but the current scripts and notes now reflect the issues encountered while bringing it up on a smaller remote VM and the fixes required to make the server start successfully.

## 🚀 Quick Start

### 1. Run Setup
This will install system dependencies, build vLLM from source, and configure optimizations.
```bash
chmod +x setup.sh
./setup.sh
```

### 2. Start the Inference Server
This script launches the vLLM server with CPU-safe defaults for the current host. It preloads Intel OpenMP and TCMalloc when available, selects the CPU backend, and only uses `numactl` when the machine actually exposes multiple NUMA nodes.
```bash
./start_vllm_cpu.sh
```
For Qwen3, the launcher also disables reasoning-mode output by default with `--default-chat-template-kwargs '{"enable_thinking": false}'`, so normal chat responses do not emit `<think>` blocks.

### 3. Run Test Script
Verify the API is working using the OpenAI SDK.
```bash
uv run test_vllm_api.py
```

## Issue-to-Solution Map

The table below records the actual problems encountered during setup and launch, plus the fix applied in this repo.

| Issue | Symptom | Fix applied |
| --- | --- | --- |
| Source build is slow | `uv` repeatedly prints `Building vllm @ file:///.../vllm` and installation takes a long time | Kept the source-build flow, but documented that this is expected on a small VM because `setup.sh` clones `vllm` and runs `uv pip install . --no-build-isolation` |
| CPU target not selected during build | Build defaults toward non-CPU paths | `setup.sh` exports `VLLM_TARGET_DEVICE=cpu` before building `vllm` |
| Python/CMake build isolation issues | Metadata generation or build steps fail to find Python headers or the active environment | `setup.sh` installs `python3-dev` and uses `uv pip install . --no-build-isolation` |
| Missing build-time packages | Build fails due to packages like `setuptools_scm`, `ninja`, or `packaging` not being available | `setup.sh` installs the required build-time Python packages into `.venv` before building |
| CPU requirements file moved inside the upstream repo | Installing CPU dependencies fails because the expected file path is absent | `setup.sh` checks multiple candidate paths and picks the available CPU requirements file |
| `vllm serve` rejects `--device cpu` | Startup fails with `vllm: error: unrecognized arguments: --device cpu` | Removed `--device cpu` from the serve command and relied on `VLLM_TARGET_DEVICE=cpu` instead |
| `libiomp` missing from `LD_PRELOAD` | Engine startup fails with `RuntimeError: libiomp is not found in LD_PRELOAD` | Updated the launcher to preload `.venv/lib/libiomp5.so` and made `setup.sh` generate the same logic |
| TCMalloc-only preload was incomplete | CPU startup reached vLLM but failed before model initialization | Launcher now constructs `LD_PRELOAD` from both Intel OpenMP and TCMalloc, keeping TCMalloc optional but `libiomp5.so` required |
| EPYC-only launcher defaults did not fit the current host | Old script assumed `Qwen2.5-7B-Instruct`, fixed NUMA pinning, and a large KV cache | Rewrote `start_vllm_cpu.sh` for the current VM: `Qwen3-1.7B`, `OMP_NUM_THREADS=2`, `VLLM_CPU_KVCACHE_SPACE=4`, optional `numactl` |
| NUMA tooling may be absent or unnecessary | Launch script would fail or over-assume topology on single-node systems | Launcher now checks for `numactl` and only uses it when installed and when more than one NUMA node is present |

## 📈 Optimizations Applied
- **Intel OpenMP preload:** Required for x86 CPU startup with current vLLM CPU builds.
- **TCMalloc preload:** Used when available for better allocator behavior under load.
- **CPU backend selection:** Enforced with `VLLM_TARGET_DEVICE=cpu`.
- **Adaptive NUMA behavior:** NUMA binding is only used when the machine topology justifies it.
- **VM-safe defaults:** Current launcher settings are sized for a smaller remote VM rather than a large bare-metal EPYC server, with `Qwen/Qwen3-1.7B` as the default model and `Qwen/Qwen3-0.6B` as the fallback if memory or latency is too tight.
- **Reasoning disabled by default:** Qwen3 is launched with `enable_thinking=false`, and the local test client sends the same request-level override to keep responses concise.

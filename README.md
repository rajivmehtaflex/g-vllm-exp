# vLLM CPU Experiment (AMD EPYC Zen 4)

This project contains a high-performance setup for running **vLLM** on CPU, specifically optimized for **AMD EPYC 9654 (Genoa)** processors on Ubuntu 24.04.

## 🚀 Quick Start

### 1. Run Setup
This will install system dependencies, build vLLM from source, and configure optimizations.
```bash
chmod +x setup.sh
./setup.sh
```

### 2. Start the Inference Server
This script clears port 8000 and launches the vLLM server with NUMA and TCMalloc optimizations.
```bash
./start_vllm_cpu.sh
```

### 3. Run Test Script
Verify the API is working using the OpenAI SDK.
```bash
uv run test_vllm_api.py
```

## 🛠 Lessons Learned: Issues & Fixes

During the setup on Ubuntu 24.04, we encountered and resolved several critical issues:

### 1. Missing Pre-built Wheels (Ubuntu 24.04 / glibc 2.39)
- **Issue:** vLLM does not yet have pre-built CPU wheels for the `manylinux_2_39` platform used by Ubuntu 24.04.
- **Fix:** Switched the installation strategy to **build from source**. This also allows the compiler to optimize specifically for the AVX-512 and VNNI instructions on the Zen 4 architecture.

### 2. CUDA Build Errors on CPU-only System
- **Issue:** The build process defaulted to looking for `CUDA_HOME` even when targeting CPU.
- **Fix:** Explicitly set `export VLLM_TARGET_DEVICE=cpu` before running the installation.

### 3. Dependency & Index Conflicts
- **Issue:** Conflicts between the PyTorch CPU index and PyPI (specifically for `setuptools`) caused "No solution found" errors.
- **Fix:** Used `uv` with `--index-strategy unsafe-best-match` to allow the resolver to pull compatible versions from multiple trusted indexes.

### 4. Build Isolation & Python Pathing
- **Issue:** CMake failed to find the Python executable and headers when `uv` used a temporary isolated build environment.
- **Fix:** Installed `python3-dev` on the system and used the `--no-build-isolation` flag to ensure the build process used the project's local virtual environment.

### 5. Build-time Requirements
- **Issue:** Since build isolation was disabled, some implicit dependencies like `setuptools_scm` were missing during the metadata generation phase.
- **Fix:** Added a manual installation step for `setuptools_scm`, `ninja`, and `packaging` into the virtual environment before starting the main build.

### 6. Repository Structure Variations
- **Issue:** The vLLM repository recently moved its CPU requirements from the root to `requirements/cpu.txt`.
- **Fix:** Updated `setup.sh` with robust path-checking logic to find the correct requirements file automatically.

### 7. Unrecognized `--device cpu` Flag
- **Issue:** The `vllm serve` command failed with an "unrecognized arguments: --device cpu" error in the source-built version.
- **Fix:** Removed the `--device cpu` flag from the command line and instead set the environment variable `export VLLM_TARGET_DEVICE=cpu` to ensure the engine correctly identifies the CPU backend.

## 📈 Optimizations Applied
- **TCMalloc:** Used for more efficient memory allocation under high concurrency.
- **NUMA Pinning:** Bound the process to NUMA node 0 to minimize memory latency on the multi-socket EPYC system.
- **AVX-512 VNNI:** Enabled via source compilation for significantly faster INT8/BF16 inference.
- **Port Management:** Added automatic cleanup of port 8000 to the start script to prevent "Address already in use" errors.

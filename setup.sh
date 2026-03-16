#!/bin/bash

# ==============================================================================
# vLLM CPU Stack Installer for AMD EPYC (Zen 4)
# Optimizations: AVX-512, VNNI, TCMalloc, NUMA Pinning
# Author: Gemini (Tailored for Cloud Native/ML Ops Professional)
# ==============================================================================

set -e  # Exit on error

echo "----------------------------------------------------------"
echo "🚀 Initializing vLLM CPU Stack Installation..."
echo "📍 Target: AMD EPYC 9654 (Genoa) on Ubuntu 24.04"
echo "----------------------------------------------------------"

# 1. Update and Install System Dependencies
echo "📦 Step 1: Installing System Dependencies..."
SUDO=""
if command -v sudo >/dev/null 2>&1; then
    SUDO="sudo"
fi

$SUDO apt-get update -y || echo "⚠️ Warning: Some repositories failed to update. Attempting to proceed..."

$SUDO apt-get install -y \
    numactl \
    libtcmalloc-minimal4 \
    libnuma-dev \
    gcc-12 \
    g++-12 \
    git \
    curl \
    cmake \
    ninja-build \
    pkg-config \
    python3-dev

# Update alternatives to ensure GCC 12 is the default for build optimizations
$SUDO update-alternatives --install /usr/bin/gcc gcc /usr/bin/gcc-12 100 --slave /usr/bin/g++ g++ /usr/bin/g++-12

# 2. Setup Isolated Python Environment using uv
echo "🐍 Step 2: Setting up Virtual Environment with uv..."
if ! command -v uv >/dev/null 2>&1; then
    echo "Installing uv..."
    curl -LsSf https://astral.sh/uv/install.sh | sh
    export PATH="$HOME/.cargo/bin:$PATH"
fi

rm -rf .venv
uv venv .venv
source .venv/bin/activate

# 3. Install vLLM from Source (Required for Ubuntu 24.04 CPU)
echo "⚙️ Step 3: Building and Installing vLLM from source..."

# Install build-time requirements
uv pip install wheel packaging ninja "setuptools>=74.1.1" setuptools-scm numpy \
    --index-strategy unsafe-best-match

# Install CPU-specific PyTorch
uv pip install torch torchvision \
    --index-strategy unsafe-best-match \
    --extra-index-url https://download.pytorch.org/whl/cpu

# Clone and build vLLM
if [ ! -d "vllm" ]; then
    git clone https://github.com/vllm-project/vllm.git
fi
cd vllm

# Find the correct CPU requirements file
REQ_FILE="requirements-cpu.txt"
if [ ! -f "$REQ_FILE" ]; then
    if [ -f "requirements/requirements-cpu.txt" ]; then
        REQ_FILE="requirements/requirements-cpu.txt"
    elif [ -f "requirements/cpu.txt" ]; then
        REQ_FILE="requirements/cpu.txt"
    fi
fi

echo "📦 Installing dependencies from $REQ_FILE..."
uv pip install -r "$REQ_FILE" --index-strategy unsafe-best-match

# Build and install for CPU
export VLLM_TARGET_DEVICE=cpu
# Clear stale build artifacts and CMake cache
rm -rf build
uv pip install . --index-strategy unsafe-best-match --no-build-isolation
cd ..

# 4. Locate preload libraries for the launcher
echo "🔍 Step 4: Configuring Memory Optimizers..."
TC_MALLOC_PATH=$(find /usr/lib -name "libtcmalloc_minimal.so.4" 2>/dev/null | head -n 1)
IOMP_PATH=$(find .venv -name "libiomp5.so" 2>/dev/null | head -n 1)

if [ -z "$IOMP_PATH" ]; then
    echo "❌ Error: libiomp5.so not found in .venv. vLLM CPU requires Intel OpenMP in LD_PRELOAD."
    exit 1
fi

echo "✅ Found Intel OpenMP at: $IOMP_PATH"
if [ -z "$TC_MALLOC_PATH" ]; then
    echo "⚠️ Warning: libtcmalloc not found. Falling back to Intel OpenMP only."
    PRELOAD_PREFIX="$IOMP_PATH"
else
    echo "✅ Found TCMalloc at: $TC_MALLOC_PATH"
    PRELOAD_PREFIX="$TC_MALLOC_PATH:$IOMP_PATH"
fi

# 5. Generate a Production-Ready Launch Script
echo "📝 Step 5: Generating optimized launcher..."

cat <<EOF > start_vllm_cpu.sh
#!/bin/bash
set -euo pipefail

VENV_PATH=".venv/bin/activate"
TCMALLOC_LIB="/usr/lib/x86_64-linux-gnu/libtcmalloc_minimal.so.4"
IOMP_LIB=".venv/lib/libiomp5.so"
MODEL_NAME="Qwen/Qwen3-1.7B"
SERVED_MODEL_NAME="qwen-local"
PORT="8000"
MAX_MODEL_LEN="8192"
MIN_AVAILABLE_MEM_GIB="8"
DEFAULT_THREADS="2"
DEFAULT_KV_CACHE_GIB="4"

if [[ ! -f "\${VENV_PATH}" ]]; then
    echo "Error: \${VENV_PATH} not found. Run ./setup.sh first."
    exit 1
fi

source "\${VENV_PATH}"

if ! command -v vllm >/dev/null 2>&1; then
    echo "Error: vllm is not installed in the virtual environment."
    exit 1
fi

AVAILABLE_MEM_GIB=\$(free -g | awk '/^Mem:/ {print \$7}')
if [[ -z "\${AVAILABLE_MEM_GIB}" || "\${AVAILABLE_MEM_GIB}" -lt "\${MIN_AVAILABLE_MEM_GIB}" ]]; then
    echo "Error: only \${AVAILABLE_MEM_GIB:-0} GiB RAM available; need at least \${MIN_AVAILABLE_MEM_GIB} GiB free."
    exit 1
fi

if [[ ! -f "\${IOMP_LIB}" ]]; then
    echo "Error: \${IOMP_LIB} not found. vLLM CPU requires libiomp5.so in LD_PRELOAD."
    exit 1
fi

CPU_FLAGS=\$(grep -m1 '^flags' /proc/cpuinfo || true)
if [[ "\${CPU_FLAGS}" != *"avx512"* ]]; then
    echo "Info: AVX-512 not detected; CPU inference will run without Zen 4 AVX-512 optimizations."
fi
if [[ "\${CPU_FLAGS}" != *"vnni"* ]]; then
    echo "Info: VNNI not detected; int8/bf16 throughput may be lower than on bare-metal EPYC."
fi

PHYSICAL_CORES=\$(lscpu | awk -F: '/^Core\\(s\\) per socket:/ {gsub(/ /, "", \$2); cores=\$2} /^Socket\\(s\\):/ {gsub(/ /, "", \$2); sockets=\$2} END {if (cores && sockets) print cores * sockets}')
if [[ -z "\${PHYSICAL_CORES}" ]]; then
    PHYSICAL_CORES="\${DEFAULT_THREADS}"
fi

THREAD_COUNT="\${DEFAULT_THREADS}"
if [[ "\${PHYSICAL_CORES}" -lt "\${THREAD_COUNT}" ]]; then
    THREAD_COUNT="\${PHYSICAL_CORES}"
fi
if [[ "\${THREAD_COUNT}" -lt 1 ]]; then
    THREAD_COUNT="1"
fi

# --- Optimization Flags ---
PRELOAD_LIBS=("\${IOMP_LIB}")
if [[ -f "\${TCMALLOC_LIB}" ]]; then
    PRELOAD_LIBS=("\${TCMALLOC_LIB}" "\${PRELOAD_LIBS[@]}")
else
    echo "Info: TCMalloc not found at \${TCMALLOC_LIB}; continuing without it."
fi

if [[ -n "\${LD_PRELOAD:-}" ]]; then
    export LD_PRELOAD="\$(IFS=:; echo "\${PRELOAD_LIBS[*]}"):\${LD_PRELOAD}"
else
    export LD_PRELOAD="\$(IFS=:; echo "\${PRELOAD_LIBS[*]}")"
fi

export OMP_NUM_THREADS="\${THREAD_COUNT}"
export VLLM_CPU_KVCACHE_SPACE=\${DEFAULT_KV_CACHE_GIB}
export VLLM_CPU_OMP_THREADS_BIND=auto
export VLLM_TARGET_DEVICE=cpu

# --- Launch Server ---
NUMA_NODES=\$(lscpu | awk -F: '/^NUMA node\\(s\\):/ {gsub(/ /, "", \$2); print \$2}')
USE_NUMACTL="false"
if command -v numactl >/dev/null 2>&1 && [[ -n "\${NUMA_NODES}" ]] && [[ "\${NUMA_NODES}" -gt 1 ]]; then
    USE_NUMACTL="true"
fi

echo "Launching vLLM on CPU with \${OMP_NUM_THREADS} threads and \${VLLM_CPU_KVCACHE_SPACE} GiB KV cache."
echo "Model: \${MODEL_NAME}"

CMD=(
    vllm
    serve
    "\${MODEL_NAME}"
    --dtype bfloat16
    --max-model-len "\${MAX_MODEL_LEN}"
    --default-chat-template-kwargs '{"enable_thinking": false}'
    --served-model-name "\${SERVED_MODEL_NAME}"
    --port "\${PORT}"
)

if [[ "\${USE_NUMACTL}" == "true" ]]; then
    exec numactl --cpunodebind=0 --membind=0 "\${CMD[@]}"
else
    exec "\${CMD[@]}"
fi
EOF

chmod +x start_vllm_cpu.sh

echo "----------------------------------------------------------"
echo "🎉 Installation Complete!"
echo "----------------------------------------------------------"
echo "To start your server with EPYC-specific optimizations:"
echo "  ./start_vllm_cpu.sh"
echo ""
echo "Note: The server will be accessible at http://localhost:8000"
echo "It natively supports both OpenAI and Anthropic API formats."

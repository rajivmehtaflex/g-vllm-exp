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

# 4. Locate TCMalloc path for the launcher
echo "🔍 Step 4: Configuring Memory Optimizers..."
TC_MALLOC_PATH=$(find /usr/lib -name "libtcmalloc_minimal.so.4" 2>/dev/null | head -n 1)

if [ -z "$TC_MALLOC_PATH" ]; then
    echo "⚠️ Warning: libtcmalloc not found. Falling back to default allocator."
    LD_PRELOAD_CMD="# LD_PRELOAD omitted: libtcmalloc not found"
else
    echo "✅ Found TCMalloc at: $TC_MALLOC_PATH"
    LD_PRELOAD_CMD="export LD_PRELOAD=$TC_MALLOC_PATH:\$LD_PRELOAD"
fi

# 5. Generate a Production-Ready Launch Script
echo "📝 Step 5: Generating optimized launcher..."

cat <<EOF > start_vllm_cpu.sh
#!/bin/bash
source .venv/bin/activate

# --- Optimization Flags ---
$LD_PRELOAD_CMD
export VLLM_CPU_KVCACHE_SPACE=40
export VLLM_CPU_OMP_THREADS_BIND=auto

# --- Launch Server ---
# We use numactl to bind to the first NUMA node (ideal for EPYC)
numactl --cpunodebind=0 --membind=0 vllm serve Qwen/Qwen2.5-7B-Instruct \\
    --device cpu \\
    --dtype bfloat16 \\
    --max-model-len 8192 \\
    --served-model-name qwen-local \\
    --port 8000
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
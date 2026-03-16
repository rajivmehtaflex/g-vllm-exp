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

if [[ ! -f "${VENV_PATH}" ]]; then
    echo "Error: ${VENV_PATH} not found. Run ./setup.sh first."
    exit 1
fi

source "${VENV_PATH}"

if ! command -v vllm >/dev/null 2>&1; then
    echo "Error: vllm is not installed in the virtual environment."
    exit 1
fi

AVAILABLE_MEM_GIB=$(free -g | awk '/^Mem:/ {print $7}')
if [[ -z "${AVAILABLE_MEM_GIB}" || "${AVAILABLE_MEM_GIB}" -lt "${MIN_AVAILABLE_MEM_GIB}" ]]; then
    echo "Error: only ${AVAILABLE_MEM_GIB:-0} GiB RAM available; need at least ${MIN_AVAILABLE_MEM_GIB} GiB free."
    exit 1
fi

if [[ ! -f "${IOMP_LIB}" ]]; then
    echo "Error: ${IOMP_LIB} not found. vLLM CPU requires libiomp5.so in LD_PRELOAD."
    exit 1
fi

CPU_FLAGS=$(grep -m1 '^flags' /proc/cpuinfo || true)
if [[ "${CPU_FLAGS}" != *"avx512"* ]]; then
    echo "Info: AVX-512 not detected; CPU inference will run without Zen 4 AVX-512 optimizations."
fi
if [[ "${CPU_FLAGS}" != *"vnni"* ]]; then
    echo "Info: VNNI not detected; int8/bf16 throughput may be lower than on bare-metal EPYC."
fi

PHYSICAL_CORES=$(lscpu | awk -F: '/^Core\(s\) per socket:/ {gsub(/ /, "", $2); cores=$2} /^Socket\(s\):/ {gsub(/ /, "", $2); sockets=$2} END {if (cores && sockets) print cores * sockets}')
if [[ -z "${PHYSICAL_CORES}" ]]; then
    PHYSICAL_CORES="${DEFAULT_THREADS}"
fi

THREAD_COUNT="${DEFAULT_THREADS}"
if [[ "${PHYSICAL_CORES}" -lt "${THREAD_COUNT}" ]]; then
    THREAD_COUNT="${PHYSICAL_CORES}"
fi
if [[ "${THREAD_COUNT}" -lt 1 ]]; then
    THREAD_COUNT="1"
fi

PRELOAD_LIBS=("${IOMP_LIB}")
if [[ -f "${TCMALLOC_LIB}" ]]; then
    PRELOAD_LIBS=("${TCMALLOC_LIB}" "${PRELOAD_LIBS[@]}")
else
    echo "Info: TCMalloc not found at ${TCMALLOC_LIB}; continuing without it."
fi

if [[ -n "${LD_PRELOAD:-}" ]]; then
    export LD_PRELOAD="$(IFS=:; echo "${PRELOAD_LIBS[*]}"):${LD_PRELOAD}"
else
    export LD_PRELOAD="$(IFS=:; echo "${PRELOAD_LIBS[*]}")"
fi

export OMP_NUM_THREADS="${THREAD_COUNT}"
export VLLM_CPU_KVCACHE_SPACE="${DEFAULT_KV_CACHE_GIB}"
export VLLM_CPU_OMP_THREADS_BIND=auto
export VLLM_TARGET_DEVICE=cpu

NUMA_NODES=$(lscpu | awk -F: '/^NUMA node\(s\):/ {gsub(/ /, "", $2); print $2}')
USE_NUMACTL="false"
if command -v numactl >/dev/null 2>&1 && [[ -n "${NUMA_NODES}" ]] && [[ "${NUMA_NODES}" -gt 1 ]]; then
    USE_NUMACTL="true"
fi

echo "Launching vLLM on CPU with ${OMP_NUM_THREADS} threads and ${VLLM_CPU_KVCACHE_SPACE} GiB KV cache."
echo "Model: ${MODEL_NAME}"

CMD=(
    vllm
    serve
    "${MODEL_NAME}"
    --dtype bfloat16
    --max-model-len "${MAX_MODEL_LEN}"
    --default-chat-template-kwargs '{"enable_thinking": false}'
    --served-model-name "${SERVED_MODEL_NAME}"
    --port "${PORT}"
)

if [[ "${USE_NUMACTL}" == "true" ]]; then
    exec numactl --cpunodebind=0 --membind=0 "${CMD[@]}"
else
    exec "${CMD[@]}"
fi

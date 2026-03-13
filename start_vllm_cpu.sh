#!/bin/bash
source .venv/bin/activate

# --- Optimization Flags ---
export LD_PRELOAD=/usr/lib/x86_64-linux-gnu/libtcmalloc_minimal.so.4:$LD_PRELOAD
export VLLM_CPU_KVCACHE_SPACE=40
export VLLM_CPU_OMP_THREADS_BIND=auto
export VLLM_TARGET_DEVICE=cpu

# --- Launch Server ---
# We use numactl to bind to the first NUMA node (ideal for EPYC)
numactl --cpunodebind=0 --membind=0 vllm serve Qwen/Qwen2.5-7B-Instruct \
    --dtype bfloat16 \
    --max-model-len 8192 \
    --served-model-name qwen-local \
    --port 8000

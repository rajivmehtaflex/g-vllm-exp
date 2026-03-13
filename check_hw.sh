#!/bin/bash

echo "========================================"
echo "          Hardware Check Script         "
echo "========================================"

echo -e "\n--- CPU Architecture & Cores ---"
lscpu

echo -e "\n--- Memory Information ---"
free -h

echo -e "\n--- NUMA Node Topology ---"
if command -v numactl >/dev/null 2>&1; then
    numactl --hardware
else
    echo "⚠️ numactl is not installed. NUMA topology cannot be verified."
fi

echo -e "\n--- Advanced Instruction Sets (AVX-512, VNNI) ---"
echo "Checking for AVX-512 and VNNI (crucial for vLLM CPU performance):"
grep -o 'avx512[^ ]*\|vnni' /proc/cpuinfo | sort -u || echo "None found."

echo -e "\n========================================"
echo "Please copy the output of this script and provide it to me."

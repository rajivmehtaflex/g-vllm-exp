#!/usr/bin/env -S uv run
# /// script
# requires-python = ">=3.12"
# dependencies = ["httpx>=0.27.0"]
# ///
"""
benchmark.py — Concurrent benchmark: vLLM (tuned) vs Ollama (plain)

Usage:
    uv run benchmark.py              # full run: vLLM then Ollama
    uv run benchmark.py --vllm-only  # skip server lifecycle, assume vLLM already up
    uv run benchmark.py --ollama-only
"""

import argparse
import asyncio
import json
import os
import signal
import statistics
import subprocess
import sys
import time

import httpx

# ---------------------------------------------------------------------------
# Configuration
# ---------------------------------------------------------------------------

VLLM_BASE_URL = "http://localhost:8000/v1"
VLLM_HEALTH_URL = "http://localhost:8000/health"
VLLM_MODEL = "qwen-local"

OLLAMA_BASE_URL = "http://localhost:11434/v1"
OLLAMA_HEALTH_URL = "http://localhost:11434/api/version"
OLLAMA_MODEL = "qwen3:4b"

CONCURRENCY_LEVELS = [1, 5, 10]
MAX_TOKENS = 200
SERVER_START_TIMEOUT = 300  # seconds

PROMPTS = [
    {"label": "short",  "text": "What is 2+2?"},
    {"label": "medium", "text": "Explain what a CPU is in 3 sentences."},
    {"label": "long",   "text": "Write a short paragraph about the history of artificial intelligence."},
]

RESULTS_FILE = "benchmark_results.json"

# ---------------------------------------------------------------------------
# Server lifecycle — vLLM
# ---------------------------------------------------------------------------

def _kill_existing_vllm() -> None:
    """Kill any process bound to port 8000, so our Popen holds the real PID."""
    result = subprocess.run(
        ["fuser", "-n", "tcp", "8000"],
        capture_output=True, text=True
    )
    for pid_str in result.stdout.split():
        try:
            os.kill(int(pid_str), signal.SIGTERM)
        except ProcessLookupError:
            pass
    if result.stdout.strip():
        time.sleep(2)  # brief wait for port to free


def start_vllm() -> subprocess.Popen:
    _kill_existing_vllm()
    print("[vLLM] Starting server via start_vllm_cpu.sh …")
    proc = subprocess.Popen(
        ["bash", "start_vllm_cpu.sh"],
        stdout=subprocess.DEVNULL,
        stderr=subprocess.DEVNULL,
        start_new_session=True,
    )
    return proc


def stop_vllm(proc: subprocess.Popen) -> None:
    print("[vLLM] Stopping server …")
    try:
        pgid = os.getpgid(proc.pid)
        os.killpg(pgid, signal.SIGTERM)
        try:
            proc.wait(timeout=15)
        except subprocess.TimeoutExpired:
            os.killpg(pgid, signal.SIGKILL)
            proc.wait(timeout=5)
    except ProcessLookupError:
        pass
    except Exception as exc:
        print(f"[vLLM] Warning during stop: {exc}")
    print("[vLLM] Server stopped.")


# ---------------------------------------------------------------------------
# Server lifecycle — Ollama
# ---------------------------------------------------------------------------

def _kill_existing_ollama() -> None:
    """Kill any ollama serve process we don't own, so our Popen holds the real PID."""
    result = subprocess.run(["pgrep", "-x", "ollama"], capture_output=True, text=True)
    for pid_str in result.stdout.strip().splitlines():
        try:
            os.kill(int(pid_str), signal.SIGTERM)
        except ProcessLookupError:
            pass
    if result.stdout.strip():
        time.sleep(2)  # brief wait for port to free


def start_ollama() -> subprocess.Popen:
    _kill_existing_ollama()
    print("[Ollama] Starting ollama serve …")
    serve_proc = subprocess.Popen(
        ["ollama", "serve"],
        stdout=subprocess.DEVNULL,
        stderr=subprocess.DEVNULL,
        start_new_session=True,
    )
    return serve_proc


def _ollama_load_model() -> None:
    """Keep the model resident in memory for the duration of the benchmark."""
    print(f"[Ollama] Loading model {OLLAMA_MODEL} into memory …")
    subprocess.run(
        ["ollama", "run", OLLAMA_MODEL, "--keepalive", "-1"],
        input=b"/bye\n",
        stdout=subprocess.DEVNULL,
        stderr=subprocess.DEVNULL,
        timeout=120,
    )


def stop_ollama(proc: subprocess.Popen) -> None:
    print("[Ollama] Unloading model …")
    try:
        subprocess.run(
            ["ollama", "stop", OLLAMA_MODEL],
            stdout=subprocess.DEVNULL,
            stderr=subprocess.DEVNULL,
            timeout=15,
        )
    except Exception:
        pass

    print("[Ollama] Stopping ollama serve …")
    try:
        pgid = os.getpgid(proc.pid)
        os.killpg(pgid, signal.SIGTERM)
        try:
            proc.wait(timeout=15)
        except subprocess.TimeoutExpired:
            os.killpg(pgid, signal.SIGKILL)
            proc.wait(timeout=5)
    except ProcessLookupError:
        pass
    except Exception as exc:
        print(f"[Ollama] Warning during stop: {exc}")
    print("[Ollama] Server stopped.")


# ---------------------------------------------------------------------------
# Readiness polling
# ---------------------------------------------------------------------------

async def wait_for_server(url: str, label: str, timeout: int = SERVER_START_TIMEOUT) -> None:
    deadline = time.monotonic() + timeout
    attempt = 0
    async with httpx.AsyncClient(timeout=5.0) as client:
        while time.monotonic() < deadline:
            try:
                r = await client.get(url)
                if r.status_code == 200:
                    print(f"[{label}] Server ready.")
                    return
            except Exception:
                pass
            attempt += 1
            if attempt % 10 == 0:
                elapsed = int(time.monotonic() - (deadline - timeout))
                print(f"[{label}] Still waiting … ({elapsed}s elapsed)")
            await asyncio.sleep(3)
    raise TimeoutError(f"[{label}] Server did not become ready within {timeout}s")


# ---------------------------------------------------------------------------
# Single streaming request
# ---------------------------------------------------------------------------

async def single_request(
    client: httpx.AsyncClient,
    base_url: str,
    model: str,
    prompt: str,
    max_tokens: int,
) -> dict:
    """Send one streaming chat-completion request; return per-request metrics."""
    payload = {
        "model": model,
        "messages": [{"role": "user", "content": prompt}],
        "max_tokens": max_tokens,
        "stream": True,
    }
    t_start = time.monotonic()
    ttft: float | None = None
    completion_tokens = 0

    try:
        async with client.stream(
            "POST",
            f"{base_url}/chat/completions",
            json=payload,
            timeout=300.0,
        ) as resp:
            resp.raise_for_status()
            async for raw_line in resp.aiter_lines():
                line = raw_line.strip()
                if not line or not line.startswith("data:"):
                    continue
                data_str = line[len("data:"):].strip()
                if data_str == "[DONE]":
                    break
                try:
                    chunk = json.loads(data_str)
                except json.JSONDecodeError:
                    continue

                choices = chunk.get("choices", [])
                if not choices:
                    continue
                delta = choices[0].get("delta", {})
                content = delta.get("content") or ""
                if content:
                    if ttft is None:
                        ttft = time.monotonic() - t_start
                    # Approximate token count: one token per ~4 chars (rough)
                    completion_tokens += max(1, len(content) // 4)

    except Exception as exc:
        total_latency = time.monotonic() - t_start
        return {
            "error": str(exc),
            "ttft": None,
            "total_latency": total_latency,
            "completion_tokens": 0,
            "tok_per_s": 0.0,
        }

    total_latency = time.monotonic() - t_start
    tok_per_s = completion_tokens / total_latency if total_latency > 0 else 0.0
    return {
        "error": None,
        "ttft": ttft,
        "total_latency": total_latency,
        "completion_tokens": completion_tokens,
        "tok_per_s": tok_per_s,
    }


# ---------------------------------------------------------------------------
# Concurrent batch
# ---------------------------------------------------------------------------

async def run_concurrent(
    base_url: str,
    model: str,
    prompt: str,
    concurrency: int,
    max_tokens: int,
) -> list[dict]:
    """Fire `concurrency` requests simultaneously; return list of per-request results."""
    limits = httpx.Limits(max_connections=concurrency + 4, max_keepalive_connections=concurrency)
    async with httpx.AsyncClient(limits=limits) as client:
        tasks = [
            single_request(client, base_url, model, prompt, max_tokens)
            for _ in range(concurrency)
        ]
        results = await asyncio.gather(*tasks)
    return list(results)


# ---------------------------------------------------------------------------
# Metric aggregation
# ---------------------------------------------------------------------------

def aggregate_metrics(results: list[dict]) -> dict:
    ttfts = [r["ttft"] for r in results if r.get("ttft") is not None]
    latencies = [r["total_latency"] for r in results if r.get("total_latency") is not None]
    total_tokens = sum(r.get("completion_tokens", 0) for r in results)
    max_latency = max(latencies) if latencies else 0.0
    agg_tok_s = total_tokens / max_latency if max_latency > 0 else 0.0
    errors = sum(1 for r in results if r.get("error"))

    return {
        "median_ttft": statistics.median(ttfts) if ttfts else None,
        "p95_latency": sorted(latencies)[int(len(latencies) * 0.95)] if latencies else None,
        "agg_throughput": agg_tok_s,
        "total_tokens": total_tokens,
        "errors": errors,
    }


# ---------------------------------------------------------------------------
# Benchmark one server across all prompts and concurrency levels
# ---------------------------------------------------------------------------

async def benchmark_server(base_url: str, model: str, label: str) -> list[dict]:
    all_rows: list[dict] = []
    for concurrency in CONCURRENCY_LEVELS:
        for prompt_info in PROMPTS:
            prompt_text = prompt_info["text"]
            prompt_label = prompt_info["label"]
            print(
                f"  [{label}] concurrency={concurrency}, prompt={prompt_label} … ",
                end="",
                flush=True,
            )
            t0 = time.monotonic()
            results = await run_concurrent(base_url, model, prompt_text, concurrency, MAX_TOKENS)
            elapsed = time.monotonic() - t0
            metrics = aggregate_metrics(results)
            print(f"done ({elapsed:.1f}s, errors={metrics['errors']})")
            all_rows.append({
                "server": label,
                "concurrency": concurrency,
                "prompt": prompt_label,
                **metrics,
            })
    return all_rows


# ---------------------------------------------------------------------------
# Result display
# ---------------------------------------------------------------------------

def fmt_s(val: float | None) -> str:
    return f"{val:.1f}s" if val is not None else "  N/A "


def fmt_tok(val: float) -> str:
    return f"{val:.1f} tok/s"


def print_table(all_rows: list[dict]) -> None:
    # Aggregate across prompts per (server, concurrency)
    from collections import defaultdict

    grouped: dict[tuple, list] = defaultdict(list)
    for row in all_rows:
        grouped[(row["concurrency"], row["server"])].append(row)

    print()
    print("══════════════════════════════════════════════════════════════════════")
    print("  BENCHMARK RESULTS: vLLM (tuned) vs Ollama (plain)")
    print("══════════════════════════════════════════════════════════════════════")
    header = f"{'Concurrency':>11} │ {'Server':<8} │ {'Median TTFT':>12} │ {'p95 Latency':>12} │ {'Agg. Throughput':>16}"
    print(header)
    print("─" * len(header))

    for concurrency in CONCURRENCY_LEVELS:
        for server in ["vLLM", "Ollama"]:
            rows = grouped.get((concurrency, server), [])
            if not rows:
                continue
            ttfts = [r["median_ttft"] for r in rows if r["median_ttft"] is not None]
            p95s = [r["p95_latency"] for r in rows if r["p95_latency"] is not None]
            agg = sum(r["agg_throughput"] for r in rows)

            median_ttft = statistics.median(ttfts) if ttfts else None
            p95 = statistics.median(p95s) if p95s else None

            print(
                f"{concurrency:>11} │ {server:<8} │ {fmt_s(median_ttft):>12} │ {fmt_s(p95):>12} │ {fmt_tok(agg):>16}"
            )
        if concurrency != CONCURRENCY_LEVELS[-1]:
            print("─" * len(header))

    print("══════════════════════════════════════════════════════════════════════")
    print()


# ---------------------------------------------------------------------------
# CLI argument parsing
# ---------------------------------------------------------------------------

def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description="Concurrent benchmark: vLLM (tuned) vs Ollama (plain)"
    )
    group = parser.add_mutually_exclusive_group()
    group.add_argument(
        "--vllm-only",
        action="store_true",
        help="Benchmark only vLLM (assumes server is already running; skips lifecycle)",
    )
    group.add_argument(
        "--ollama-only",
        action="store_true",
        help="Benchmark only Ollama (assumes server is already running; skips lifecycle)",
    )
    return parser.parse_args()


# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------

async def main() -> None:
    args = parse_args()
    all_rows: list[dict] = []

    # ── vLLM ──────────────────────────────────────────────────────────────
    if not args.ollama_only:
        vllm_proc = None
        try:
            if not args.vllm_only:
                vllm_proc = start_vllm()
            print("[vLLM] Waiting for server to be ready …")
            await wait_for_server(VLLM_HEALTH_URL, "vLLM")
            print("[vLLM] Running benchmark …")
            rows = await benchmark_server(VLLM_BASE_URL, VLLM_MODEL, "vLLM")
            all_rows.extend(rows)
        finally:
            if vllm_proc is not None:
                stop_vllm(vllm_proc)
                # Brief pause to let ports free up before starting Ollama
                await asyncio.sleep(3)

    # ── Ollama ────────────────────────────────────────────────────────────
    if not args.vllm_only:
        ollama_proc = None
        try:
            if not args.ollama_only:
                ollama_proc = start_ollama()
            print("[Ollama] Waiting for server to be ready …")
            await wait_for_server(OLLAMA_HEALTH_URL, "Ollama")
            if not args.ollama_only:
                _ollama_load_model()
            print("[Ollama] Running benchmark …")
            rows = await benchmark_server(OLLAMA_BASE_URL, OLLAMA_MODEL, "Ollama")
            all_rows.extend(rows)
        finally:
            if ollama_proc is not None:
                stop_ollama(ollama_proc)

    # ── Results ───────────────────────────────────────────────────────────
    if all_rows:
        print_table(all_rows)
        with open(RESULTS_FILE, "w") as f:
            json.dump(all_rows, f, indent=2)
        print(f"Results saved to {RESULTS_FILE}")
    else:
        print("No results collected.")


if __name__ == "__main__":
    asyncio.run(main())

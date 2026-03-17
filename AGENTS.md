# Repository Guidelines

## Project Structure & Module Organization
This repository is a thin wrapper around a local CPU-focused vLLM workflow.

- `setup.sh`: installs system packages, creates `.venv`, and builds `vllm` for CPU use.
- `check_hw.sh`: quick hardware/CPU capability sanity checks before benchmarking.
- `start_vllm_cpu.sh`: launches the local OpenAI-compatible server with CPU-safe defaults.
- `test_vllm_api.py`: interactive client for prompting the local server, with streaming output and token metrics.
- `benchmark.py`: side-by-side request benchmark script for vLLM vs Ollama.
- `benchmark_run.log`: generated benchmark output and environment notes (regenerate as needed).
- `README.md`: setup notes and issue-to-solution mapping for this environment.
- `vllm/`: upstream vLLM source checkout used by `setup.sh`. Treat it as vendored code unless you are intentionally modifying upstream internals.

## Change Tracking & Codebase Triage
- Before editing, review the last 4 hours of activity:
  - `git log --since='4 hours ago' --oneline --decorate`
- Include a quick working-tree check before and after edits:
  - `git status --short`
- For broad edits, confirm touched files with:
  - `rg --files -g '*.sh' -g '*.py' -g 'README.md' -g 'AGENTS.md'`

## Build, Test, and Development Commands
- `./setup.sh`: install dependencies and build the local CPU vLLM environment.
- `./start_vllm_cpu.sh`: start the local server on port `8000`.
- `uv run test_vllm_api.py`: open the interactive test client.
- `uv run test_vllm_api.py "Explain NUMA briefly"`: run a one-shot prompt.
- `python3 -m py_compile test_vllm_api.py`: quick syntax check for the client script.
- `bash -n setup.sh && bash -n start_vllm_cpu.sh`: shell syntax validation before committing script changes.

## Coding Style & Naming Conventions
Use Python 3.12+ and shell scripts compatible with `bash`. Prefer 4-space indentation in Python and straightforward, defensive shell scripting with `set -euo pipefail` where appropriate. Use descriptive snake_case for Python functions and variables. Keep launcher and setup changes explicit rather than overly abstract; this repo favors operational clarity over framework-heavy structure.

## Testing Guidelines
There is no formal test suite yet; validation is mostly smoke-test based.

- Run syntax checks before committing.
- Start the server and verify it with `uv run test_vllm_api.py`.
- When changing launch behavior, confirm streaming output, token metrics, and CPU startup on the current host.
- Name future Python tests `test_*.py` to match existing patterns.

## Commit & Pull Request Guidelines
Recent history uses short imperative messages, often with prefixes such as `feat:` and `refactor(...)`. Follow that style, for example: `feat: add streaming CLI metrics` or `fix(scripts): preload libiomp for CPU startup`.

PRs should include:
- a short summary of the user-visible change,
- any setup or runtime impact,
- exact verification commands run,
- relevant logs or screenshots when debugging startup/runtime issues.

## Security & Configuration Tips
Do not commit secrets, tokens, or machine-specific credentials. Keep GitHub auth in the environment or local config, not in tracked files. Prefer environment variables for runtime overrides, and document any host-specific assumptions in `README.md`.

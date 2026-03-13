# GEMINI.md - Project Context

## Project Overview
`g-vllm-exp` is a Python-based experimental project. It is managed using `uv` and currently serves as a template or starting point for experiments, likely related to vLLM (Virtual Large Language Model) or similar technologies, given the name.

- **Main Technologies:** Python (>= 3.12), `uv` (for package management).
- **Structure:**
  - `main.py`: The primary entry point for the application.
  - `pyproject.toml`: Project metadata and dependency configuration.
  - `uv.lock`: Dependency lock file.

## Building and Running

### Prerequisites
- [uv](https://github.com/astral-sh/uv) installed on your system.

### Running the Project
To execute the main script:
```bash
uv run main.py
```

### Managing Dependencies
To add a new dependency:
```bash
uv add <package-name>
```

To synchronize the environment:
```bash
uv sync
```

## Development Conventions
- **Language:** Python 3.12+
- **Tooling:** Use `uv` for all environment and dependency management.
- **Entry Point:** The core logic should be invoked via `main.py`.
- **Style:** Adhere to standard Python (PEP 8) conventions.

import argparse
import sys
import time

import openai


client = openai.OpenAI(
    base_url="http://localhost:8000/v1",
    api_key="local-vllm",
)

EXIT_COMMANDS = {"quit", "exit"}
CHAT_TEMPLATE_KWARGS = {"enable_thinking": False}


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description="Send a prompt to the local vLLM server with streaming output."
    )
    parser.add_argument(
        "prompt",
        nargs="?",
        help="User prompt to send to the local vLLM server. If omitted, the script enters interactive mode.",
    )
    parser.add_argument(
        "--max-tokens",
        type=int,
        default=100,
        help="Maximum number of output tokens to generate.",
    )
    parser.add_argument(
        "--system-prompt",
        default="You are a helpful assistant.",
        help="System prompt to prepend to the conversation.",
    )
    return parser.parse_args()


def normalize_prompt(raw_prompt: str) -> str | None:
    prompt = raw_prompt.strip()
    if not prompt:
        return None
    return prompt


def print_metrics(duration: float, time_to_first_token: float | None, usage) -> None:
    prompt_tokens = getattr(usage, "prompt_tokens", 0) if usage else 0
    completion_tokens = getattr(usage, "completion_tokens", 0) if usage else 0
    total_tokens = (
        getattr(usage, "total_tokens", prompt_tokens + completion_tokens)
        if usage
        else prompt_tokens + completion_tokens
    )

    print("\n--- Metrics ---")
    print(f"Latency: {duration:.2f}s")
    if time_to_first_token is not None:
        print(f"Time to first token: {time_to_first_token:.2f}s")
    else:
        print("Time to first token: unavailable")
    print(f"Prompt tokens: {prompt_tokens}")
    print(f"Completion tokens: {completion_tokens}")
    print(f"Total tokens: {total_tokens}")

    if duration > 0:
        print(f"Overall throughput: {total_tokens / duration:.2f} tok/s")
        print(f"Completion throughput: {completion_tokens / duration:.2f} tok/s")

    if (
        time_to_first_token is not None
        and duration > time_to_first_token
        and completion_tokens > 0
    ):
        generation_time = duration - time_to_first_token
        print(f"Decode throughput: {completion_tokens / generation_time:.2f} tok/s")
    print("---------------")


def test_chat_completion(prompt: str, max_tokens: int, system_prompt: str) -> None:
    print(f"Prompt: {prompt}")
    print("\n--- Streaming Response ---")

    try:
        start_time = time.time()
        first_token_time = None
        usage = None

        stream = client.chat.completions.create(
            model="qwen-local",
            messages=[
                {"role": "system", "content": system_prompt},
                {"role": "user", "content": prompt},
            ],
            max_tokens=max_tokens,
            stream=True,
            stream_options={"include_usage": True},
            extra_body={"chat_template_kwargs": CHAT_TEMPLATE_KWARGS},
        )

        for chunk in stream:
            if getattr(chunk, "usage", None) is not None:
                usage = chunk.usage

            if not chunk.choices:
                continue

            delta = chunk.choices[0].delta
            content = getattr(delta, "content", None)
            if not content:
                continue

            if first_token_time is None:
                first_token_time = time.time() - start_time

            sys.stdout.write(content)
            sys.stdout.flush()

        duration = time.time() - start_time
        print("\n--------------------------")
        print(f"Success. Response time: {duration:.2f}s")
        print_metrics(duration, first_token_time, usage)

    except Exception as exc:
        print(f"\nError connecting to vLLM: {exc}")
        print("Make sure the server is running with ./start_vllm_cpu.sh")


def run_interactive_loop(max_tokens: int, system_prompt: str) -> None:
    print("Interactive mode. Type 'quit' or 'exit' to stop.")

    while True:
        try:
            raw_prompt = input("Prompt: ")
        except EOFError:
            print("\nExiting.")
            break
        except KeyboardInterrupt:
            print("\nExiting.")
            break

        prompt = normalize_prompt(raw_prompt)
        if prompt is None:
            continue

        if prompt.lower() in EXIT_COMMANDS:
            print("Exiting.")
            break

        test_chat_completion(prompt, max_tokens, system_prompt)
        print()


if __name__ == "__main__":
    args = parse_args()

    if args.prompt is not None:
        prompt = normalize_prompt(args.prompt)
        if prompt is None:
            print("No prompt provided. Exiting.")
            raise SystemExit(1)
        test_chat_completion(prompt, args.max_tokens, args.system_prompt)
    else:
        run_interactive_loop(args.max_tokens, args.system_prompt)

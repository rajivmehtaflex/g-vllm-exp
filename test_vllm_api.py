import openai
import time

# Configuration for local vLLM server
# Note: No real API key is required, but the SDK expects a string.
client = openai.OpenAI(
    base_url="http://localhost:8000/v1",
    api_key="local-vllm"
)

def test_chat_completion():
    print("🚀 Testing Chat Completion with local vLLM...")
    try:
        start_time = time.time()
        response = client.chat.completions.create(
            model="qwen-local",
            messages=[
                {"role": "system", "content": "You are a helpful assistant."},
                {"role": "user", "content": "Explain why AMD EPYC processors are good for LLM inference in 2 sentences."}
            ],
            max_tokens=100
        )
        duration = time.time() - start_time
        
        print(f"\n✅ Success! (Response time: {duration:.2f}s)")
        print(f"--- Response ---")
        print(response.choices[0].message.content)
        print(f"----------------")
        
    except Exception as e:
        print(f"\n❌ Error connecting to vLLM: {e}")
        print("💡 Make sure you have started the server with ./start_vllm_cpu.sh")

if __name__ == "__main__":
    test_chat_completion()

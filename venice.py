import os

from dotenv import load_dotenv
from openai import OpenAI

load_dotenv()

client = OpenAI(
    api_key=os.environ["VENICE_API_KEY"],
    base_url=os.environ.get("VENICE_BASE_URL", "https://api.venice.ai/api/v1"),
)


def chat(model: str, message: str) -> str:
    response = client.chat.completions.create(
        model=model,
        messages=[{"role": "user", "content": message}],
    )
    return response.choices[0].message.content


def list_models() -> list[str]:
    return [m.id for m in client.models.list()]


if __name__ == "__main__":
    import sys

    if len(sys.argv) > 1:
        models = list_models()
        print("> Available models:")
        for m in models:
            print(f"  - {m}")
    else:
        print(chat("claude-fable-5", "Say hello in one line."))
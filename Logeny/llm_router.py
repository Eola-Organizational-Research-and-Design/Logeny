from huggingface_model_runner import generate_map_reduce_response as hf_response
from gemini_model_runner import configure_gemini, run_gemini_chat
# from openai_model_runner import run_openai_chat  # future
# from claude_model_runner import run_claude_chat  # future

import os

def route_model_response(provider, model_name, prompt, context_window=2048, api_key=None):
    if provider.lower() == "huggingface":
        return hf_response(prompt, model_name, context_window)

    elif provider.lower() == "gemini":
        if not api_key:
            raise ValueError("Gemini API key is required")
        configure_gemini(api_key)
        return run_gemini_chat(model_name, prompt)

    # elif provider.lower() == "openai":
    #     return run_openai_chat(model_name, prompt, api_key)

    raise ValueError(f"Unsupported provider: {provider}")

# llm_api_handler.py

import requests
import json
from typing import Dict, Any, Optional

class LLMAPIError(Exception):
    """Custom exception for LLM API errors."""
    pass

def make_api_call(
    api_url: str,
    method: str,
    headers: Dict[str, str],
    payload: Optional[Dict[str, Any]] = None,
    api_key: str = None
) -> str:
    """
    Handles the core logic of making an API request.

    Args:
        api_url: The URL of the API endpoint.
        method: The HTTP method (e.g., "GET", "POST").
        headers: HTTP headers to include in the request.
        payload: The request payload (for POST, PUT, etc.).
        api_key: (Optional) API key to include in headers.

    Returns:
        The API response as a string.

    Raises:
        LLMAPIError: If the API request fails.
    """

    if api_key:
        headers["Authorization"] = f"Bearer {api_key}"  # Or however the API expects the key

    try:
        response = requests.request(method, api_url, headers=headers, json=payload)
        response.raise_for_status()  # Raise HTTPError for bad responses (4xx or 5xx)
        return response.text  # Or response.json() if you expect JSON

    except requests.exceptions.RequestException as e:
        raise LLMAPIError(f"API request failed: {e}")

def call_gemini_api(
    prompt: str,
    api_key: str,
    model_name: str = "gemini-pro",  # Default model
    max_output_tokens: int = 2048,
    history: Optional[list] = None  # Optional chat history
) -> str:
    """
    Calls the Gemini API with the given prompt.

    Args:
        prompt: The user's input prompt.
        api_key: The Gemini API key.
        model_name: The specific Gemini model to use.
        max_output_tokens: Maximum tokens in the response.
        history: (Optional) Chat history to provide context.

    Returns:
        The model's response as a string.

    Raises:
        LLMAPIError: If the API call fails.
    """

    api_url = f"https://generativelanguage.googleapis.com/v1beta/models/{model_name}:generateContent"  # Adjust as needed
    headers = {"Content-Type": "application/json"}
    payload = {
        "contents": [{"parts": [{"text": prompt}]}],  # Basic text input
        "generationConfig": {"maxOutputTokens": max_output_tokens}
    }

    if history:
        # Format history appropriately for Gemini (adjust as needed)
        formatted_history = [{"role": item["sender"], "parts": [{"text": item["message"]}]} for item in history]
        payload["contents"] = formatted_history + payload["contents"]  # Prepend history

    try:
        return make_api_call(api_url, "POST", headers, payload, api_key)

    except LLMAPIError as e:
        raise LLMAPIError(f"Gemini API call failed: {e}")

# Add more API calling functions for other LLMs (e.g., call_openai_api, etc.)

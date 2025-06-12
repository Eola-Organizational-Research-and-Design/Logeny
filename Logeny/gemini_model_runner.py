import google.generativeai as genai
import os

_gemini_models = {}

def configure_gemini(api_key):
    genai.configure(api_key=api_key)

def run_gemini_chat(model_name, prompt):
    if model_name not in _gemini_models:
        _gemini_models[model_name] = genai.GenerativeModel(model_name)
    model = _gemini_models[model_name]
    chat = model.start_chat()
    response = chat.send_message("Please format your response in Markdown. " + prompt)
    try:
        output = response.candidates[0]['content'].parts[0].text.strip()
    except Exception:
        output = response.text.strip()
    return output

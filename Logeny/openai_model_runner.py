import openai
import os

def openai_model_runner(prompt, model="gpt-3.5-turbo", api_key=None, system_prompt=None, temperature=0.7, max_tokens=1024):
    if not api_key:
        api_key = os.getenv("OPENAI_API_KEY")
    if not api_key:
        raise ValueError("No API key provided and OPENAI_API_KEY not set in environment.")

    client = openai.OpenAI(api_key=api_key)

    messages = []
    if system_prompt:
        messages.append({"role": "system", "content": system_prompt})
    messages.append({"role": "user", "content": "Please format your response in Markdown. " + prompt})

    try:
        response = client.chat.completions.create(
            model=model,
            messages=messages,
            temperature=temperature,
            max_tokens=max_tokens
        )
        output = response.choices[0].message.content.strip()
        return f"```markdown\n{output}\n```"
    except Exception as e:
        raise RuntimeError(f"OpenAI API call failed: {e}")

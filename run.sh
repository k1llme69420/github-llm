#!/bin/bash
set -e

echo "Reassembling model weights..."
cat weights/model_part_* > model.gguf

echo "Installing llama-cpp-python..."
pip install llama-cpp-python --quiet

echo "Running inference..."
python3 - << 'EOF'
import os, json
from llama_cpp import Llama

history_file = "memory/history.json"
prompt = os.environ["USER_PROMPT"]
clear_history = os.environ["CLEAR_HISTORY"].lower() == "true"

# 1. Load or initialize history
if clear_history or not os.path.exists(history_file):
    history = [{"role": "system", "content": "You are a helpful, concise AI assistant."}]
else:
    with open(history_file, "r") as f:
        history = json.load(f)
    if not history:
        history = [{"role": "system", "content": "You are a helpful, concise AI assistant."}]

# 2. Append current user prompt
history.append({"role": "user", "content": prompt})

# 3. Safely trim history while maintaining strict User/Assistant alternation
system_prompt = history[0]
messages = history[1:]

# Keep at most the last 6 messages to fit context window
if len(messages) > 6:
    messages = messages[-6:]

# Ensure the trimmed list always starts with a 'user' message (never an orphaned 'assistant')
while messages and messages[0]["role"] != "user":
    messages.pop(0)

trimmed_history = [system_prompt] + messages

# 4. Run inference
# Note: If your model requires a specific format (e.g., chat_format="chatml" or "llama-3"), add it here:
llm = Llama(
    model_path="model.gguf", 
    n_ctx=2048, 
    n_threads=4, 
    verbose=False
    # chat_format="chatml"  <-- Uncomment and adjust if your model needs a specific format
)

response = llm.create_chat_completion(
    messages=trimmed_history, 
    max_tokens=512
)
reply = response["choices"][0]["message"]["content"]

# 5. Append assistant reply and save back to history
history.append({"role": "assistant", "content": reply})

with open(history_file, "w") as f:
    json.dump(history, f, indent=2)

# 6. Output to GitHub Step Summary
summary_path = os.environ.get("GITHUB_STEP_SUMMARY")
if summary_path:
    quoted_prompt = "\n".join(f"> {line}" if line.strip() else ">" for line in prompt.splitlines())
    quoted_reply = "\n".join(f"> {line}" if line.strip() else ">" for line in reply.splitlines())
    
    with open(summary_path, "w", encoding="utf-8") as f:
        f.write(f"### User\n{quoted_prompt}\n\n### Assistant\n{quoted_reply}\n")
EOF

echo "Saving updated chat history to branch..."
cd memory
git config user.name "GitHub Actions LLM"
git config user.email "actions@github.com"
git add history.json
git commit -m "Chat turn: $(date -u +'%Y-%m-%d %H:%M:%S UTC')" || echo "No changes to commit"
git push origin chat-history
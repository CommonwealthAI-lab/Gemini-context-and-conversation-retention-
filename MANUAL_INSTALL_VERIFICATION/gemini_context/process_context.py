
import json
import re

def parse_conversation(raw_text):
    conversation_history = []
    lines = raw_text.split('\n')
    current_user_message_lines = []
    current_gemini_message_lines = []
    is_user_turn = True # Assume first message is user's
    in_tool_output_block = False

    for line in lines:
        stripped_line = line.strip()

        # Detect start of tool output block
        if stripped_line.startswith('╭───'):
            in_tool_output_block = True
            # Append the tool output block start to the current message
            if is_user_turn:
                current_user_message_lines.append(line)
            else:
                current_gemini_message_lines.append(line)
            continue
        # Detect end of tool output block
        elif stripped_line.startswith('╰───'):
            in_tool_output_block = False
            # Append the tool output block end to the current message
            if is_user_turn:
                current_user_message_lines.append(line)
            else:
                current_gemini_message_lines.append(line)
            continue

        # If inside a tool output block, append the line as is
        if in_tool_output_block:
            if is_user_turn:
                current_user_message_lines.append(line)
            else:
                current_gemini_message_lines.append(line)
            continue

        # Handle user messages
        if stripped_line.startswith('>'):
            # If there's a pending Gemini message, save the turn
            if current_gemini_message_lines:
                conversation_history.append({
                    "user": "\n".join(current_user_message_lines).strip(),
                    "gemini": "\n".join(current_gemini_message_lines).strip()
                })
                current_user_message_lines = []
                current_gemini_message_lines = []
            current_user_message_lines.append(stripped_line[1:].strip())
            is_user_turn = True
        # Handle Gemini messages
        elif stripped_line.startswith('✦'):
            current_gemini_message_lines.append(stripped_line[1:].strip())
            is_user_turn = False
        # Handle continuation lines for current message
        elif stripped_line: # Only add non-empty lines
            if is_user_turn:
                current_user_message_lines.append(stripped_line)
            else:
                current_gemini_message_lines.append(stripped_line)

    # Add any remaining messages
    if current_user_message_lines or current_gemini_message_lines:
        conversation_history.append({
            "user": "\n".join(current_user_message_lines).strip(),
            "gemini": "\n".join(current_gemini_message_lines).strip()
        })

    return conversation_history

# Read the raw conversation text from the file
with open("D:\\gemini_context\\context to be added.txt", "r", encoding="latin-1") as f:
    raw_conversation_text = f.read()

# Load existing context.json
with open("D:\\gemini_context\\context.json", "r", encoding="latin-1") as f:
    existing_context = json.load(f)

# Parse the new conversation
new_conversation_entries = parse_conversation(raw_conversation_text)

# Append to existing conversation history
existing_context["conversation_history"].extend(new_conversation_entries)

# Write updated context.json
with open("D:\\gemini_context\\context.json", "w", encoding="utf-8") as f:
    json.dump(existing_context, f, indent=4)

print("Context updated successfully.")

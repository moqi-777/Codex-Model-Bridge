"""
LiteLLM hook for providers that reject repeated system messages or list-form
message content. It also strips <think> blocks from MiniMax streaming output.
"""
from litellm.integrations.custom_logger import CustomLogger


def _flatten_content(content):
    if isinstance(content, str):
        return content
    if isinstance(content, list):
        parts = []
        for block in content:
            if isinstance(block, dict):
                t = block.get("type")
                if t in ("text", "input_text"):
                    parts.append(block.get("text", ""))
                else:
                    parts.append(str(block.get("text", "")))
        return "\n".join(p for p in parts if p)
    return str(content) if content is not None else ""


def _merge_messages(messages):
    merged = []
    for msg in messages:
        role = msg.get("role")
        content = _flatten_content(msg.get("content"))
        if (
            merged
            and merged[-1].get("role") == role
            and role in ("system", "user", "assistant")
            and not msg.get("tool_calls")
            and not msg.get("name")
            and not merged[-1].get("tool_calls")
            and not merged[-1].get("name")
        ):
            merged[-1]["content"] = (merged[-1].get("content") or "") + "\n\n" + content
        else:
            new_msg = dict(msg)
            new_msg["content"] = content
            merged.append(new_msg)
    return merged


def _normalize_responses_input(data):
    instructions = data.get("instructions") or ""
    items = data.get("input")
    if not isinstance(items, list):
        return data
    new_items = []
    extra_sys = []
    for it in items:
        if not isinstance(it, dict):
            new_items.append(it)
            continue
        role = it.get("role")
        if role in ("system", "developer"):
            extra_sys.append(_flatten_content(it.get("content")))
        else:
            new_items.append(it)
    if extra_sys:
        data["instructions"] = "\n\n".join(p for p in [instructions] + extra_sys if p)
        data["input"] = new_items
    return data


_THINK_OPEN = "<think>"
_THINK_CLOSE = "</think>"


def _strip_full_text(text):
    if not text:
        return text
    out, i, in_think = [], 0, False
    while i < len(text):
        if in_think:
            close = text.find(_THINK_CLOSE, i)
            if close == -1:
                return "".join(out)
            i = close + len(_THINK_CLOSE)
            in_think = False
        else:
            opn = text.find(_THINK_OPEN, i)
            if opn == -1:
                out.append(text[i:])
                break
            out.append(text[i:opn])
            i = opn + len(_THINK_OPEN)
            in_think = True
    return "".join(out)


def _strip_think_text(text, state):
    if not text:
        return "", ""
    buf = state.get("tail_buffer", "") + text
    out, reasoning = [], []
    i = 0
    while i < len(buf):
        if state.get("in_think"):
            close_pos = buf.find(_THINK_CLOSE, i)
            if close_pos == -1:
                keep = max(i, len(buf) - len(_THINK_CLOSE) + 1)
                reasoning.append(buf[i:keep])
                state["tail_buffer"] = buf[keep:]
                return "".join(out), "".join(reasoning)
            reasoning.append(buf[i:close_pos])
            i = close_pos + len(_THINK_CLOSE)
            state["in_think"] = False
        else:
            open_pos = buf.find(_THINK_OPEN, i)
            if open_pos == -1:
                keep = max(i, len(buf) - len(_THINK_OPEN) + 1)
                out.append(buf[i:keep])
                state["tail_buffer"] = buf[keep:]
                return "".join(out), "".join(reasoning)
            out.append(buf[i:open_pos])
            i = open_pos + len(_THINK_OPEN)
            state["in_think"] = True
    state["tail_buffer"] = ""
    return "".join(out), "".join(reasoning)


def _set_field(obj, name, value):
    if isinstance(obj, dict):
        obj[name] = value
        return
    try:
        setattr(obj, name, value)
    except Exception:
        pass


def _strip_item(item):
    if item is None:
        return
    content = item.get("content") if isinstance(item, dict) else getattr(item, "content", None)
    if isinstance(content, list):
        for cb in content:
            t = cb.get("text") if isinstance(cb, dict) else getattr(cb, "text", None)
            if isinstance(t, str):
                _set_field(cb, "text", _strip_full_text(t))


class MergeMessagesHook(CustomLogger):
    async def async_pre_call_hook(self, user_api_key_dict, cache, data, call_type):
        if not data:
            return data
        model = str(data.get("model", "")).lower()
        if "minimax" not in model:
            return data
        if call_type in ("aresponses", "responses"):
            _normalize_responses_input(data)
        else:
            msgs = data.get("messages")
            if isinstance(msgs, list):
                data["messages"] = _merge_messages(msgs)
        return data

    async def async_post_call_streaming_iterator_hook(self, user_api_key_dict, response, request_data):
        model = str((request_data or {}).get("model", "")).lower()
        if "minimax" not in model:
            async for chunk in response:
                yield chunk
            return
        state = {"in_think": False, "tail_buffer": ""}
        async for chunk in response:
            ev_type = getattr(chunk, "type", None)
            if ev_type is None and isinstance(chunk, dict):
                ev_type = chunk.get("type")
            ev_type_str = getattr(ev_type, "value", None) or (str(ev_type) if ev_type is not None else "")

            if ev_type_str == "response.output_text.delta":
                delta_text = chunk.get("delta") if isinstance(chunk, dict) else getattr(chunk, "delta", "")
                emit, _ = _strip_think_text(delta_text or "", state)
                if not emit:
                    continue
                _set_field(chunk, "delta", emit)
            elif ev_type_str in ("response.output_text.done", "response.content_part.done"):
                t = chunk.get("text") if isinstance(chunk, dict) else getattr(chunk, "text", None)
                if isinstance(t, str):
                    _set_field(chunk, "text", _strip_full_text(t))
                part = chunk.get("part") if isinstance(chunk, dict) else getattr(chunk, "part", None)
                if part is not None:
                    pt = part.get("text") if isinstance(part, dict) else getattr(part, "text", None)
                    if isinstance(pt, str):
                        _set_field(part, "text", _strip_full_text(pt))
            elif ev_type_str == "response.output_item.done":
                _strip_item(chunk.get("item") if isinstance(chunk, dict) else getattr(chunk, "item", None))
            elif ev_type_str == "response.completed":
                resp = chunk.get("response") if isinstance(chunk, dict) else getattr(chunk, "response", None)
                if resp is not None:
                    output = resp.get("output") if isinstance(resp, dict) else getattr(resp, "output", None)
                    if isinstance(output, list):
                        for item in output:
                            _strip_item(item)
            yield chunk


proxy_handler_instance = MergeMessagesHook()

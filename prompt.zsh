# prompt.zsh — `prompt` node-creation helper (stdlib extension)
#
# Role: create a one-line semantic context node under $AGENT_NODES_PATH,
# exactly as the kernel used to: mkdir the node dir, write `context` and
# `parent`. No validation, no chmod, no `plug` file.
#
# Why this lives in the stdlib and not the kernel:
#   - Creating a node is one repeated operation over an existing primitive
#     (a directory with two files). The kernel already owns the primitive
#     (node chain, credential claim/drop); the convenience of spelling it
#     `prompt <id> <content> [parent]` is a tool built on top, not mechanism.
#   - Remove it and the mechanism layer is still complete: `agsh init` and a
#     plain `mkdir` + `echo` (the chain protocol's own procedure) do the same.
#   - The shell is the extension mechanism: sourcing this file is all it takes.
#
# Usage: add to ~/.agshrc. i18n.zsh is optional — list it first so the banner
# line and the help row are translated; without it the module speaks English.
#   source /abs/path/agsh-stdlib/i18n.zsh     # optional: the i18n suite
#   source /abs/path/agsh-stdlib/prompt.zsh
#
# The kernel no longer lists `prompt` on its banner/help — it is not a kernel
# command — so this module advertises itself through the suite's services:
#   - banner: _agsh_banner_add prompt prompt.banner 1 (position 1, so the
#     composed banner reads exactly as it did before the command moved out of
#     the kernel). Without kernel-slots.zsh it degrades to the legacy string
#     prepend, so the module still works when the suite is absent.
#   - help:   _agsh_help_add Commands 'prompt <id> <content> [parent]' ...
#     Without help.zsh the row is simply absent (no error).
# Both are re-applied on every language load through _agsh_hooks_apply, so a
# runtime `agent-lang set <id>` re-renders the line/row in the new language.
#
# Lifecycle: the function persists after `agent unload`, like any extension
# sourced from ~/.agshrc; it goes away with the shell. `_agsh_unload` removes
# it (and its banner/help rows) when the suite is unloaded explicitly.

# ─── i18n seam: module-owned text, suite-owned services ──────────────────────
# This module owns its behaviour *and* its text. It must stay usable without the
# i18n suite: dropping i18n.zsh — or the whole suite — must not break `prompt`.
# So the text primitives carry a minimal guard of their own, and only the
# optional *services* (banner assembler, structured help) are probed at call
# time through the registry.
#
#   channel A — suite absent: the guard below defines _agsh_def/_agsh_t/_agsh_tf
#               over the shared container, resolving <lang>.<key> -> en.<key>.
#               With no pack, _agsh_lang stays "en", so the module simply speaks
#               English. Nothing is sourced; nothing is required.
#   channel B — suite present: i18n-core.zsh is sourced and its real
#               implementations overwrite the guard's, adding the fallback
#               chain, the fmt-key registry and AGSH_I18N_STRICT.
#
# Order-independent: the module "defines if missing", the core "always defines".
# Core first -> the guard is skipped; module first -> the core wins on arrival.
# Either way the shell ends up with the real core in place.
typeset -gA _agsh_txt _agsh_fmt_keys
typeset -g  _agsh_lang="${_agsh_lang:-en}"
if ! (( $+functions[_agsh_t] )); then
  _agsh_def() {
    _agsh_txt[en.$1]="$2"
    (( $# > 2 )) && _agsh_fmt_keys[$1]=1
    print -r -- "$2"
  }
  _agsh_t() {
    local t="${_agsh_txt[${_agsh_lang}.$1]:-${_agsh_txt[en.$1]:-}}"
    if [[ -n "$t" ]]; then print -r -- "$t"
    elif (( $# > 1 )); then print -r -- "${@:2}"; fi
  }
  _agsh_tf() {
    local t="${_agsh_txt[${_agsh_lang}.$1]:-${_agsh_txt[en.$1]:-}}"
    [[ -n "$t" ]] || return 0
    if [[ -n "${_agsh_fmt_keys[$1]:-}" ]]; then printf -- "$t" "${@:2}"
    else print -r -- "$t"; fi
  }
  _agsh_have() { return 1 }   # no registry yet: every optional service is absent
fi

# Channel B: take the real core if it is on disk (idempotent — sourcing it twice
# is safe). It overwrites the guard's functions and brings registry.zsh along.
[[ -f "${${(%):-%x}:A:h}/i18n-core.zsh" ]] \
  && source "${${(%):-%x}:A:h}/i18n-core.zsh"

# ─── module text (namespace: prompt.*) ───────────────────────────────────────
# One text, one place: the English lives here, the call sites look it up (no
# English fallback argument repeated at the call site). _agsh_def echoes its
# text by contract; redirected, because a module is sourced on every new shell.
# Dynamic values are declared fmt so they go through _agsh_tf (printf) and a
# translation may reorder the %s placeholders.
_agsh_def prompt.usage 'usage: prompt <id> <content> [parent]' >/dev/null
_agsh_txt[zh.prompt.usage]='用法: prompt <id> <content> [parent]'
_agsh_def prompt.usage_hint '  Creates a prompt node under %s/<id>/\n' fmt >/dev/null
_agsh_txt[zh.prompt.usage_hint]='  在 %s/<id>/ 下创建一个提示词节点\n'
_agsh_def prompt.created "[prompt] created node '%s' -> %s/\n" fmt >/dev/null
_agsh_txt[zh.prompt.created]="[prompt] 已创建节点 '%s' -> %s/\n"
_agsh_def prompt.banner '  prompt     - Create a prompt node' >/dev/null
_agsh_txt[zh.prompt.banner]='  prompt     - 创建提示词节点'
_agsh_def prompt.help.prompt 'Create a prompt node' >/dev/null
_agsh_txt[zh.prompt.help.prompt]='创建提示词节点'

# ─── prompt: one-line semantic context node creation ─────────────────────────
# Example: prompt security-audit "You are a security audit expert"
prompt() {
  local id="$1"
  local content="$2"
  local parent="${3:-root}"
  if (( $# < 2 )); then
    _agsh_t prompt.usage >&2
    _agsh_tf prompt.usage_hint "$AGENT_NODES_PATH" >&2
    return 1
  fi
  mkdir -p "$AGENT_NODES_PATH/$id"
  echo "$content" > "$AGENT_NODES_PATH/$id/context"
  echo "$parent" > "$AGENT_NODES_PATH/$id/parent"
  _agsh_tf prompt.created "$id" "$AGENT_NODES_PATH/$id" >&2
}
export -f prompt >/dev/null 2>&1 || true

# ─── suite surfaces ──────────────────────────────────────────────────────────
# Runs now and on every language load (registered below), so the banner line
# and the help row follow a runtime `agent-lang set`. Both calls are
# idempotent: _agsh_banner_add replaces an owner's entry, _agsh_help_add
# replaces a command's row.
_agsh_prompt_apply() {
  if _agsh_have banner; then
    _agsh_banner_add prompt prompt.banner 1
  else
    # Legacy path: no banner assembler (suite not installed) — prepend to the
    # kernel string as before, idempotently.
    local line
    line="$(_agsh_t prompt.banner)"
    if [[ -n "$line" && "$_AGENT_BANNER_TEXT" != *"$line"* ]]; then
      _AGENT_BANNER_TEXT="$line"$'\n'"$_AGENT_BANNER_TEXT"
    fi
  fi
  if _agsh_have help; then
    _agsh_help_add Commands 'prompt <id> <content> [parent]' prompt.help.prompt
  fi
  return 0
}

# ─── unload ──────────────────────────────────────────────────────────────────
# Removes the function and its advertised surfaces. The remove calls are
# guarded: a previous unload hook (help.zsh) may already have unfunctioned the
# registry API, and the core's no-op placeholders are gone after a full unload.
_agsh_prompt_unload() {
  (( $+functions[_agsh_banner_remove] )) && _agsh_banner_remove prompt
  (( $+functions[_agsh_help_remove] )) \
    && _agsh_help_remove 'prompt <id> <content> [parent]'
  (( ${+_agsh_hooks_apply} )) \
    && _agsh_hooks_apply=("${(@)_agsh_hooks_apply:#_agsh_prompt_apply}")
  (( ${+_agsh_hooks_unload} )) \
    && _agsh_hooks_unload=("${(@)_agsh_hooks_unload:#_agsh_prompt_unload}")
  unfunction prompt _agsh_prompt_apply _agsh_prompt_unload 2>/dev/null
  return 0
}

[[ " ${_agsh_hooks_apply[*]} " == *" _agsh_prompt_apply "* ]] \
  || _agsh_hooks_apply+=(_agsh_prompt_apply)
[[ " ${_agsh_hooks_unload[*]} " == *" _agsh_prompt_unload "* ]] \
  || _agsh_hooks_unload+=(_agsh_prompt_unload)

_agsh_prompt_apply

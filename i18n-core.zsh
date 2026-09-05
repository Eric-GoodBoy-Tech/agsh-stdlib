# i18n-core.zsh — dependency-free text core of the AgentShell i18n suite (L0)
#
# Role: hold the text registry and the lookup/format primitives. This file
# knows no kernel, no language pack and no module: it is the layer every other
# piece of the suite builds on, and it can be sourced on its own. Sourcing it
# twice is safe (idempotent: no pack is loaded, no hook is run).
#
# Contract (frozen; L1/L2/L3 implement against these signatures, do not change):
#
#   _agsh_txt        global assoc: "<lang>.<key>" -> text
#   _agsh_lang       current language id (default en)
#   _agsh_fmt_keys   global assoc: <key> -> 1  (text holds printf placeholders)
#
#   _agsh_def <key> '<text>' [fmt]   register en.<key>; record fmt keys in
#                                    _agsh_fmt_keys; echo the text back so a
#                                    call site may also inline it
#   _agsh_pack_def <key> '<text>' [fmt]  same, but silent (for language packs)
#   _agsh_lookup <key> [own...]      echo the text (internal resolution)
#   _agsh_t  <key> [own...]          print -r the text (safe for any text)
#   _agsh_tf <key> [printf-args...]  printf the text; only for fmt keys, a
#                                    non-fmt key warns (STRICT) and degrades
#                                    to print -r instead of being used as a
#                                    format string
#
# Resolution order: <lang>.<key> -> en.<key> -> own fallback -> empty.
# AGSH_I18N_STRICT=1 makes a missing <lang>.<key> print
#   [i18n] missing key: <key> (lang=<lang>)
# on stderr; the returned text is unchanged.
#
# Dependencies: this core is dependency-free and never registers a placeholder.
# Cross-component availability is asked of registry.zsh (sourced below):
# `_agsh_have <id>` is 0 when that provider announced itself, 1 otherwise, and a
# provider owns its own name — this file knows none. A caller therefore gates an
# optional service on _agsh_have; when the provider is absent its service
# function (`_agsh_banner_add`, `_agsh_help_add`, ...) simply does not exist and
# the caller degrades instead of failing.
#
# Key namespace: the first segment of a key is its owner ("kernel.", "prompt.",
# "i18n.", ...). A module file X.zsh may only write X.* keys; language packs
# under lang/ are exempt. Enforced by tools/i18n-lint.zsh.

# ─── registry ───────────────────────────────────────────────────────────────
# The suite's one cross-component dispatch mechanism (see registry.zsh).
# Sourced here so every module that already sources the core also gets it;
# idempotent.
source "${${(%):-%x}:A:h}/registry.zsh"

typeset -gA _agsh_txt
typeset -g  _agsh_lang="${_agsh_lang:-en}"
typeset -gA _agsh_fmt_keys
typeset -gA _agsh_pack_meta
typeset -ga _agsh_hooks_apply
typeset -ga _agsh_hooks_unload
typeset -g  _agsh_i18n_dir="${${(%):-%x}:A:h}"

# Register the English text for a key. One text, one place: call sites look the
# key up instead of repeating the English string as their own fallback.
_agsh_def() {
  local key="$1" text="$2" fmt="${3:-}"
  _agsh_txt[en.$key]="$text"
  [[ -n "$fmt" ]] && _agsh_fmt_keys[$key]=1
  print -r -- "$text"
}

# Same, silent: language packs register dozens of keys at source time and must
# not paint the terminal on every new shell.
_agsh_pack_def() {
  _agsh_def "$@" >/dev/null
}

# Internal resolution: <lang>.<key> -> en.<key> -> own fallback -> nothing.
_agsh_lookup() {
  local key="$1"; shift
  local lang="${_agsh_lang:-en}"
  local text="${_agsh_txt[$lang.$key]}"
  if [[ -z "$text" ]]; then
    if [[ -n "${AGSH_I18N_STRICT:-}" ]]; then
      print -r -- "[i18n] missing key: $key (lang=$lang)" >&2
    fi
    text="${_agsh_txt[en.$key]}"
  fi
  if [[ -n "$text" ]]; then
    print -r -- "$text"
  elif (( $# )); then
    print -r -- "$@"
  fi
}

# Safe lookup: the text is data, never a format string.
_agsh_t() {
  _agsh_lookup "$@"
}

# Formatted lookup: only for keys explicitly declared fmt. A translation that
# reorders the placeholders is fine; a translation containing a stray % is not
# a crash, because _agsh_t never routes through printf.
_agsh_tf() {
  local key="$1"; shift
  local lang="${_agsh_lang:-en}"
  local text="${_agsh_txt[$lang.$key]}"
  [[ -n "$text" ]] || text="${_agsh_txt[en.$key]}"
  if [[ -z "${_agsh_fmt_keys[$key]:-}" ]]; then
    if [[ -n "${AGSH_I18N_STRICT:-}" ]]; then
      print -r -- "[i18n] key not declared fmt: $key (use _agsh_t)" >&2
    fi
    [[ -n "$text" ]] && print -r -- "$text"
    return 0
  fi
  if [[ -z "$text" ]]; then
    if [[ -n "${AGSH_I18N_STRICT:-}" ]]; then
      print -r -- "[i18n] missing key: $key (lang=$lang)" >&2
    fi
    return 0
  fi
  printf -- "$text" "$@"
}

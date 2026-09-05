# help.zsh — L2: structured help registry and renderer (i18n suite plugin service)
#
# Role: turn `agent help` from two hand-maintained 20-line literals (the
# kernel's English one and the pack's translation) into structure + text:
#
#   - help.zsh owns the page: which sections exist, their order, their column
#     widths, and the left column of every row.
#   - a language pack owns the words: one key per header, per section title and
#     per row description.
#   - a module owns its own row: `_agsh_help_add Commands 'foo <id>' foo.help`
#     appends to the section without touching any pack or the kernel.
#
# The kernel is not modified: it still has its own `_agent_help_en`, and
# kernel-slots.zsh routes the `_agsh_help` slot to `_agsh_help_render` when
# this file is installed (probed by presence, see _agsh_help_dispatch).
#
# API
#   _agsh_help_section <name> <field-width>   declare a section (order, width)
#   _agsh_help_add <section> <command> <key>  register/replace a row
#   _agsh_help_remove <command>               drop a row (all sections)
#   _agsh_help_render [--base] [lang]         print the page
#   _agsh_help_readme [lang]                  print a markdown table
#
# The description column starts at 2 + field-width, measured in display width
# (${(m)#}), which reproduces the pre-migration layout byte for byte.
# `--base` renders only the kernel rows, so a test (or the self-check) can
# compare against the legacy oracle while modules keep adding rows.

(( $+functions[_agsh_t] )) || return 0

typeset -ga _agsh_help_sections
typeset -ga _agsh_help_items        # "section\x1fcommand\x1fkey", in order
typeset -ga _agsh_help_base_cmds    # the kernel rows (help.zsh's own)
typeset -gA _agsh_help_width        # section -> field width

_agsh_help_section() {
  emulate -L zsh
  local name="${1:-}" width="${2:-32}"
  [[ -n "$name" ]] || return 1
  [[ "$width" == <-> ]] || return 1
  (( ${+_agsh_help_width[$name]} )) || _agsh_help_sections+=("$name")
  _agsh_help_width[$name]="$width"
  return 0
}

# Register or replace one row. Re-registering the same command keeps its
# position (idempotent across re-sourcing), which matters because a module may
# be sourced twice in one shell.
_agsh_help_add() {
  emulate -L zsh
  local section="${1:-}" cmd="${2:-}" key="${3:-}"
  [[ -n "$section" && -n "$cmd" && -n "$key" ]] || return 1
  (( ${+_agsh_help_width[$section]} )) || _agsh_help_section "$section" 32 || return 1
  local -a out=()
  local entry rest
  local -i replaced=0
  for entry in "${_agsh_help_items[@]}"; do
    rest="${entry#*$'\x1f'}"
    if [[ "${rest%%$'\x1f'*}" == "$cmd" ]]; then
      out+=("${section}"$'\x1f'"${cmd}"$'\x1f'"${key}")
      replaced=1
    else
      out+=("$entry")
    fi
  done
  (( replaced )) || out+=("${section}"$'\x1f'"${cmd}"$'\x1f'"${key}")
  _agsh_help_items=("${out[@]}")
  return 0
}

_agsh_help_remove() {
  emulate -L zsh
  local cmd="${1:-}"
  [[ -n "$cmd" ]] || return 1
  local -a out=()
  local entry rest
  for entry in "${_agsh_help_items[@]}"; do
    rest="${entry#*$'\x1f'}"
    [[ "${rest%%$'\x1f'*}" == "$cmd" ]] || out+=("$entry")
  done
  _agsh_help_items=("${out[@]}")
  return 0
}

# "  <command><pad><description>", description at column 2 + width.
_agsh_help__row() {
  local cmd="$1" width="$2" desc="$3"
  local -i pad=$(( width - ${(m)#cmd} ))
  (( pad < 1 )) && pad=1
  printf '  %s%*s%s' "$cmd" "$pad" '' "$desc"
}

_agsh_help__is_base() {
  local cmd="$1" base
  for base in "${_agsh_help_base_cmds[@]}"; do
    [[ "$base" == "$cmd" ]] && return 0
  done
  return 1
}

_agsh_help_render() {
  emulate -L zsh
  local base_only=0 lang=""
  while (( $# )); do
    case "$1" in
      --base) base_only=1; shift ;;
      *)      lang="$1"; shift ;;
    esac
  done
  [[ -n "$lang" ]] || lang="${_agsh_lang:-en}"
  local saved="${_agsh_lang:-en}"
  _agsh_lang="$lang"

  local -a lines
  lines+=("$(_agsh_t kernel.help.header)" "")

  local section entry rest cmd key
  local -a body
  local -i first=1
  for section in "${_agsh_help_sections[@]}"; do
    body=()
    for entry in "${_agsh_help_items[@]}"; do
      [[ "${entry%%$'\x1f'*}" == "$section" ]] || continue
      rest="${entry#*$'\x1f'}"
      cmd="${rest%%$'\x1f'*}"
      key="${rest#*$'\x1f'}"
      (( base_only )) && ! _agsh_help__is_base "$cmd" && continue
      body+=("$(_agsh_help__row "$cmd" "${_agsh_help_width[$section]}" "$(_agsh_t "$key")")")
    done
    (( ${#body} )) || continue
    (( first )) || lines+=("")
    first=0
    lines+=("$(_agsh_t "kernel.help.section.${section:l}")")
    lines+=("${body[@]}")
  done

  _agsh_lang="$saved"
  print -r -- "${(F)lines}"
}

_agsh_help_readme() {
  emulate -L zsh
  local lang="${1:-${_agsh_lang:-en}}"
  local saved="${_agsh_lang:-en}"
  _agsh_lang="$lang"
  local esc_cmd esc_desc
  print -r -- '| Section | Command | Description |'
  print -r -- '| --- | --- | --- |'
  local section entry rest cmd key
  for section in "${_agsh_help_sections[@]}"; do
    for entry in "${_agsh_help_items[@]}"; do
      [[ "${entry%%$'\x1f'*}" == "$section" ]] || continue
      rest="${entry#*$'\x1f'}"
      cmd="${rest%%$'\x1f'*}"
      key="${rest#*$'\x1f'}"
      esc_cmd="${cmd//|/\\|}"
      esc_desc="$(_agsh_t "$key")"
      esc_desc="${esc_desc//|/\\|}"
      print -r -- "| ${section} | \`${esc_cmd}\` | ${esc_desc} |"
    done
  done
  _agsh_lang="$saved"
}

# ─── kernel page (structure only; text lives in the packs) ───────────────────
_agsh_help_section Commands 32
_agsh_help_section Keybindings 8
_agsh_help_section Env 32

typeset -ga _agsh_help_base
_agsh_help_base=(
  'Commands|credential claim <id>|kernel.help.credential_claim'
  'Commands|credential drop|kernel.help.credential_drop'
  'Commands|agent help|kernel.help.agent_help'
  'Commands|agent unload|kernel.help.agent_unload'
  'Commands|agent debug tail|kernel.help.agent_debug_tail'
  'Commands|agent debug cat|kernel.help.agent_debug_cat'
  'Keybindings|Ctrl+G|kernel.help.ctrl_g'
  'Keybindings|Ctrl+T|kernel.help.ctrl_t'
  'Env|AGENT_API_KEY|kernel.help.env_api_key'
  'Env|AGENT_BASE_URL|kernel.help.env_base_url'
  'Env|AGENT_MODEL|kernel.help.env_model'
  'Env|AGENT_EXEC_DELAY=2|kernel.help.env_exec_delay'
  'Env|AGENT_OUTPUT_MAX_LENGTH=10000|kernel.help.env_output_max_length'
  'Env|AGENT_DEBUG=false|kernel.help.env_debug'
  'Env|AGENT_EXEC_TIMEOUT=0|kernel.help.env_exec_timeout'
  'Env|AGENT_REASONING_EFFORT=high|kernel.help.env_reasoning_effort'
  'Env|AGENT_API_TTFT_TIMEOUT=120|kernel.help.env_ttft_timeout'
)

_agsh_help_base_cmds=()
local _entry _section _rest _cmd _key
for _entry in "${_agsh_help_base[@]}"; do
  _section="${_entry%%|*}"
  _rest="${_entry#*|}"
  _cmd="${_rest%%|*}"
  _key="${_rest#*|}"
  _agsh_help_add "$_section" "$_cmd" "$_key"
  _agsh_help_base_cmds+=("$_cmd")
done
unset _entry _section _rest _cmd _key

# ─── unload ──────────────────────────────────────────────────────────────────
# Self-contained: the suite's _agsh_unload runs the unload hooks, so this file
# cleans up its own registry instead of asking i18n.zsh to know about it.
_agsh_help_unload() {
  unfunction _agsh_help_section _agsh_help_add _agsh_help_remove \
             _agsh_help_render _agsh_help_readme _agsh_help__row \
             _agsh_help__is_base _agsh_help_unload 2>/dev/null
  unset _agsh_help_sections _agsh_help_items _agsh_help_base_cmds \
        _agsh_help_width _agsh_help_base 2>/dev/null
  return 0
}
[[ " ${_agsh_hooks_unload[*]} " == *" _agsh_help_unload "* ]] \
  || _agsh_hooks_unload+=(_agsh_help_unload)

# ─── registry ────────────────────────────────────────────────────────────────
# Announce this layer under the id "help"; consumers ask _agsh_have help /
# _agsh_call help.<member>. The id lives here, not in registry.zsh.
_agsh_register help \
  add=_agsh_help_add remove=_agsh_help_remove render=_agsh_help_render \
  readme=_agsh_help_readme

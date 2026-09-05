#!/usr/bin/env zsh
# i18n-lint.zsh — static lint for the AgentShell i18n registry
#
# Usage: zsh tools/i18n-lint.zsh [stdlib-dir]
# Exit:  0 = clean, 1 = violations (one per line on stderr), 2 = not a stdlib dir
#
# It reads the sources, never sources them, so it is safe to run anywhere and
# it also catches a pack that would fail to load.
#
# Checks
#   a) every <lang>.<key> with lang != en has an en counterpart
#   b) in a stdlib-root module file X.zsh every key is written as X.<key>;
#      lang/*.zsh packs are exempt (they own every namespace they translate)
#   c) no key is defined twice for the same language
#   d) every key passed to _agsh_tf is declared fmt, and its _agsh_def line
#      contains a '%' (a fmt key without a placeholder is a bug either way)
#   e) a stdlib-root module that writes text must be self-sufficient: it must
#      carry its own channel-A guard (a code line testing $+functions[_agsh_t])
#      so it still works when the i18n suite is absent. The i18n suite's own
#      layers are exempt by name (suite_layers below); lang/*.zsh packs are
#      exempt exactly as in (b).
#
# The exemption list for (e) is the suite_layers array; the marker it looks
# for is deliberately the *code* form of the guard, not a comment, so a file
# cannot claim self-sufficiency it does not implement.
#
# Note: the regexes live in variables. A literal RHS of =~ in zsh is subject to
# glob interpretation and '[' would be mangled; an unquoted variable is not.

emulate -L zsh

local root="${1:-${0:A:h:h}}"
if [[ ! -d "$root/lang" ]]; then
  print -r -- "[i18n-lint] not a stdlib dir: $root" >&2
  exit 2
fi

typeset -A en_keys seen fmt_keys tf_keys
local -a errors
local file stem line key lang where
local -i lineno

local re_def='_agsh_(pack_)?def[[:space:]]+([A-Za-z0-9_.-]+)'
local re_txt='_agsh_txt\[([A-Za-z0-9_-]+)\.([A-Za-z0-9_.-]+)\]'
local re_tf='_agsh_tf[[:space:]]+([A-Za-z0-9_.-]+)'
local re_scan='^[[:space:]]*[^[:space:]#]'

# Suite layers: files that *are* the i18n suite and may depend on the core.
# Their names are the whole exemption list for check (e); anything else that
# writes text is a module and must carry its own channel-A guard.
local -a suite_layers=(i18n-core.zsh registry.zsh i18n.zsh kernel-slots.zsh help.zsh)
typeset -A writes guard mods

local -a files=("$root"/*.zsh(N) "$root"/lang/*.zsh(N))

for file in "${files[@]}"; do
  stem="${${file:t}:r}"
  local is_pack=0
  [[ "$file" == */lang/* ]] && is_pack=1

  # Scan code lines only (first non-blank char is not '#'): the doc blocks
  # quote the API and must not be mistaken for registrations. Teardown lists
  # (`unfunction _agsh_def _agsh_tf ...`) name the API without touching text.
  while IFS= read -r line; do
    lineno="${line%%:*}"
    line="${line#*:}"
    [[ "$line" == *unfunction* ]] && continue
    # channel-A guard marker: a code line probing the text API's presence
    [[ "$line" == *'$+functions[_agsh_t]'* ]] && guard[$file]=1

    if [[ "$line" =~ $re_def ]]; then
      writes[$file]=1
      key="${match[2]}"
      lang=en
      if [[ "$line" == *[[:space:]]fmt* ]]; then
        fmt_keys[$key]=1
        [[ "$line" == *%* ]] || errors+=("$file:$lineno: fmt key '$key' has no '%' in its text")
      fi
    elif [[ "$line" =~ $re_txt ]]; then
      writes[$file]=1
      lang="${match[1]}"
      key="${match[2]}"
    else
      if [[ "$line" =~ $re_tf ]]; then
        tf_keys[${match[1]}]=1
      fi
      continue
    fi

    if (( ! is_pack )); then
      [[ "$key" == "$stem".* ]] \
        || errors+=("$file:$lineno: key '$key' outside its namespace '$stem.'")
    fi

    where="$file:$lineno"
    if [[ -n "${seen[$lang.$key]:-}" ]]; then
      errors+=("$file:$lineno: duplicate definition of '$lang.$key' (first at ${seen[$lang.$key]})")
    else
      seen[$lang.$key]="$where"
    fi
    [[ "$lang" == en ]] && en_keys[$key]=1
  done < <(grep -nE "$re_scan" "$file")
done

for key in ${(k)seen}; do
  [[ "$key" == en.* ]] && continue
  [[ -n "${en_keys[${key#*.}]:-}" ]] \
    || errors+=("${seen[$key]}: '$key' has no en counterpart")
done

for key in ${(k)tf_keys}; do
  [[ -n "${fmt_keys[$key]:-}" ]] \
    || errors+=("key '$key' is passed to _agsh_tf but never declared fmt")
done

# (e) module self-sufficiency. Runs after the scan so every file's code lines
# have been seen. A file that writes text, is not a pack and is not a suite
# layer must carry the channel-A guard.
for file in "${files[@]}"; do
  [[ -n "${writes[$file]:-}" ]] || continue
  [[ "$file" == */lang/* ]] && continue
  [[ " ${suite_layers[*]} " == *" ${file:t} "* ]] && continue
  mods[$file]=1
  [[ -n "${guard[$file]:-}" ]] \
    || errors+=("$file: writes text but carries no channel-A guard (a code line testing \$+functions[_agsh_t]); a module must stay usable while the i18n suite is absent")
done

if (( ${#errors} )); then
  local e
  for e in "${errors[@]}"; do
    print -r -- "[i18n-lint] $e" >&2
  done
  print -r -- "[i18n-lint] ${#errors} violation(s)" >&2
  exit 1
fi

print -r -- "[i18n-lint] ok: ${#seen} key(s), ${#fmt_keys} fmt, ${#tf_keys} _agsh_tf call site(s), ${#mods} module guard(s)"
exit 0

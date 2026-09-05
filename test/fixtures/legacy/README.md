# legacy/ — pre-i18n-migration text oracle

Captured 2026-09-09 by node `mig2-i18n` from the working tree **before** any
i18n rewrite, in an isolated environment (isolated HOME with an `.agshrc` that
sources only `agsh-stdlib/i18n.zsh`; isolated TMPDIR; isolated AGENT_NODES_PATH;
`LANG` per file; no production `~/.agshrc`).

Why: `agsh-stdlib/lang/zh.zsh` is untracked (no git history) and gets rewritten
by the i18n suite work. These files are the byte-exact behaviour the new
implementation must reproduce.

| file | produced by |
|------|-------------|
| `help.en.txt` | `_agent_help_en` (kernel, agent.zsh) |
| `help.zh.txt` | `_agent_help_zh` (legacy zh pack) |
| `banner-base.en.txt` | `print -r -- "$_AGENT_BANNER_TEXT"`, LANG=en (kernel default, 5 lines + trailing blank) |
| `banner-base.zh.txt` | same, LANG=zh (legacy zh pack, 5 lines + trailing blank) |
| `cred-help.{en,zh}.txt` | `_agent_credential_help_{en,zh}` (stderr) |
| `cred-set.{en,zh}.txt` | `CREDENTIAL=testid _agent_credential_status_{en,zh} set` (stderr) |
| `cred-clear.{en,zh}.txt` | `_agent_credential_status_{en,zh} cleared` (stderr) |

`capture.sh` reproduces them, but only against the pre-migration tree.
`banner-base.*` intentionally excludes the `prompt` banner line added later by
`prompt.zsh`; the composed banner is `prompt-line + "\n" + banner-base`.
`help.*` intentionally excludes the `prompt` / `agent-lang` command rows added
later by the module/help registry.

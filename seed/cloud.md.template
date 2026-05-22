---
name: <cloud-name-kebab-case>
provider: <firebase | azure | aws | gcp | cloudflare | vercel | netlify | self-hosted | other>
kind: <hosting | database | compute | registry | storage | ml | queue | auth | cdn | monitoring | other>
environments: [<env>, <env>, ...]   # keys from .claude/environments.json
# Optional: explicit cross-reference to another cloud entry. Useful for
# deploy chains like "AKS pulls images from ACR" — declare it here.
pulls_from: []
---

# <Cloud / surface name>

> One file per cloud resource / deployment surface. Filename matches
> the frontmatter `name`. Cross-reference siblings via `pulls_from` if
> they're operationally linked (e.g. AKS pulls from ACR; web hosting
> reads from a separate RTDB).
>
> This file describes a *surface*. The *workflows* that touch the
> surface (deploy pipelines, multi-step rollouts) live in `/release`,
> a project script, or `.claude/playlists.md` — not here.

**Provider.** <e.g. Firebase / Azure / AWS / etc.>
**Project / Account.** <project ID, subscription ID, account ID — whatever identifies the cloud-side resource>
**Region.** <if applicable>
**Live URL.** <if public-facing; omit if internal>

---

## Auth

How a human / CI authenticates to this surface.

- **Local (interactive):** `<command>` (e.g. `firebase login`, `az login`, `aws sso login --profile <profile>`)
- **CI / service account:** `<path or env var pattern>` (e.g. service account JSON at `.secrets/firebase-sa.json` — gitignored; or `AZURE_SP_*` env vars set by the runner)
- **Rotation cadence:** <if relevant>

---

## Commands

| Purpose | Command |
|---|---|
| **Deploy (`<env>`)** | `<command>` |
| **Deploy (`<env>`)** | `<command>` |
| **Rollback** | `<command>` |
| **Status / health** | `<command>` |
| **Logs** | `<command or console URL>` |

Use one command row per environment (local / staging / prod). Drop
rows that don't apply.

---

## Config files

Tool-native config files in the repo that configure this surface.
The kit doesn't manage these — the tools do — but document them so
new contributors know where to look.

- `<path>` — <what it configures>
- ...

---

## Gotchas

Sharp edges someone touching this resource needs to know. Past
incidents, surprising defaults, things you can't change easily once
set.

- ...

---

## References

- Docs: <URL>
- Console: <URL>
- Cost dashboard: <URL>

---

*Last verified working: <YYYY-MM-DD>. Update this date when you
re-confirm the auth / commands still work.*

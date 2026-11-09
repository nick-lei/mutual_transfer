# Project Skills

Installed for this project on 2026-11-06 using Codex's skill-installer.
The skill folders contain the complete upstream packages.

| Skill | Source | Branch | Pinned Commit |
| --- | --- | --- | --- |
| `impeccable` | https://github.com/pbakaus/impeccable | `main` | `c3bb418ee38ee49a6b999b7752c1368f3123a2bd` |
| `design-taste-frontend` | https://github.com/Leonxlnx/taste-skill | `taste-skill-v2` | `9da1763c950baed17a69158a5f4c76f8f85bf49b` |

Source directories:

- Impeccable: `.agents/skills/impeccable` in its repository.
- Taste: `skills/taste-skill` in its repository. Other optional skills were not installed.

## Usage

These are project-local Agent Skills. Use `$impeccable` or
`$design-taste-frontend` in a Codex request for this project.

Impeccable includes design review, audit, layout, polish, accessibility, and
other interface workflows. The installed Taste v2 targets public-facing
websites and explicitly excludes dashboards and app screens. Respect each
skill's scope when working on the Flutter desktop application.

## Runtime And Verification

- All 63 Impeccable source files and 29 Taste source files were verified against
  their pinned Git blobs. The Windows `.cmd` launcher uses CRLF from the GitHub
  archive; its content matches after line-ending normalization.
- Impeccable skill version: `4.8.0`. Engine version: `0.1.18`.
- The official Windows x64 engine is installed at
  `impeccable/scripts/bin/windows-x64/impeccable.exe` relative to this directory.
- Git retains the pinned skill sources and upstream licenses; downloaded engine
  binaries are local-only. On a fresh checkout, the Impeccable launcher prepares
  the required engine when first used.
- Engine SHA-256:
  `8f61e96b0c97001546a824d79b44f46b423b560f3eb1a0cc44a8695a1b395d9f`.
  It matches the upstream checksum manifest and GitHub release digest.
- `impeccable/scripts/impeccable.cmd engine-probe` succeeds.
- Taste's `scripts/draw.mjs --list directions` succeeds using the existing
  bundled Node.js `24.22.1` runtime.

The system default Node.js is `18.14.2`. For Taste scripts that need Node 22+,
use the existing bundled runtime without changing the system installation:

```powershell
$tasteNode = 'C:\Users\Administrator\.cache\codex-runtimes\codex-primary-runtime\dependencies\node\bin\node.exe'
& $tasteNode '.agents\skills\design-taste-frontend\scripts\draw.mjs' --list directions
```

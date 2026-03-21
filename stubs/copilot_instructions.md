# GitHub Copilot Instructions

<!-- 
This file provides additional context to GitHub Copilot.
It's read automatically when Copilot CLI starts in this repository.
-->

## Session Workflow

This project uses session workflow for AI context continuity.
See `.session/docs/README.md` for quick reference.

Use `next.md` as the structured follow-up artifact for the next session. Keep `notes.md` for broader running notes and compatibility.

**Agents:**
- `invoke session.start --issue N` — Development session from GitHub issue (planning phase by default)
- `invoke session.start --auto --issue N` — Auto until the next human gate; otherwise through `publish`, then stop for manual/custom review
- `invoke session.start --auto --copilot-review --issue N` — Full auto with Copilot review before merge
- `invoke session.start --spec 001-feature` — Spec Kit session
- `invoke session.start "description"` — Development session (positional description)
- `invoke session.start --spike "description"` — Spike/research (no PR)
- `invoke session.start --debug "description"` — Debug/troubleshooting session (no PR by default)
- `invoke session.start --resume` — Resume active session
- `invoke session.review` — Run the default or overridden custom review agent after publish
- `invoke session.finalize` — Post-merge cleanup (after PR merge)
- `invoke session.wrap` — End session

**Project context:**
- `.session/project-context/technical-context.md` - Stack, build/test commands
- `.session/project-context/constitution-summary.md` - Quality standards

## Code Style

<!-- TODO: Add code style preferences -->

## Testing

<!-- TODO: Add testing conventions -->

## Documentation

<!-- TODO: Add documentation standards -->

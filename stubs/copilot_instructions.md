## Session Workflow

This project uses session workflow for AI context continuity.
See `.session/docs/agnostic-workflow-guide.md` for quick reference.

**Debug Workflow:**
- `invoke session.start --debug "description"`
SECTION
- next.md for handoff
- `invoke session.start --brainstorm "description"` — Start a development/spike session with an upfront brainstorm
- `invoke session.start --operational "description"` — Operational batch/pipeline session
- ./.session/scripts/bash/session-audit.sh --all --summary

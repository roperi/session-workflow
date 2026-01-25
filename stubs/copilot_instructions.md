# GitHub Copilot Instructions

<!-- 
This file provides additional context to GitHub Copilot.
It's read automatically when Copilot CLI starts in this repository.
-->

## Session Workflow

This project uses session workflow for AI context continuity.

**Commands:**
- `/session.start --issue N` - Development session from GitHub issue
- `/session.start --spec 001-feature` - Spec Kit session
- `/session.start "description"` - Development session (positional description)
- `/session.start --spike "description"` - Spike/research (no PR)
- `/session.start --resume` - Resume active session
- `/session.finalize` - Post-merge cleanup (after PR merge)
- `/session.wrap` - End session

**Project context:**
- `.session/project-context/technical-context.md` - Stack, build/test commands
- `.session/project-context/constitution-summary.md` - Quality standards

## Code Style

<!-- TODO: Add code style preferences -->

## Testing

<!-- TODO: Add testing conventions -->

## Documentation

<!-- TODO: Add documentation standards -->

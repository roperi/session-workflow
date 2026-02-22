# Project Name

<!-- 
This file is read by AI assistants (GitHub Copilot CLI, etc.) at the start of every session.
Keep it concise - this consumes context window.
-->

## Quick Start

```bash
# Build
# TODO: Add build command

# Test
# TODO: Add test command

# Lint
# TODO: Add lint command
```

## Session Workflow

This project uses session workflow for AI context continuity.

**Agents:**
- `invoke session.start --issue N` - Development session from GitHub issue
- `invoke session.start --spec 001-feature` - Spec Kit session
- `invoke session.start "description"` - Development session (positional description)
- `invoke session.start --spike "description"` - Spike/research (no PR)
- `invoke session.start --resume` - Resume active session
- `invoke session.finalize` - Post-merge cleanup (after PR merge)
- `invoke session.wrap` - End session

**Project context:**
- `.session/project-context/technical-context.md` - Stack, build/test commands
- `.session/project-context/constitution-summary.md` - Quality standards

## Project Structure

<!-- TODO: Describe key directories and files -->

## Conventions

<!-- TODO: Add project-specific conventions -->

# Session Workflow

A lightweight, portable session management system for AI-assisted development. Provides context continuity across AI sessions and structured work tracking.

**📖 Full documentation: [GUIDE.md](GUIDE.md)**

## Quick Install

```bash
curl -sSL https://raw.githubusercontent.com/roperi/session-workflow/main/install.sh | bash
```

Or clone and run locally:

```bash
git clone https://github.com/roperi/session-workflow.git
cd your-project
../session-workflow/install.sh
```

## What Gets Installed

```
your-repo/
├── AGENTS.md                    # AI bootstrap (created if missing)
├── .github/
│   ├── copilot_instructions.md  # Copilot config (created if missing)
│   ├── agents/session.*.agent.md
│   └── prompts/session.*.prompt.md
└── .session/
    ├── scripts/bash/            # Workflow scripts
    ├── templates/               # Note templates  
    ├── docs/                    # Quick reference
    ├── project-context/         # Customize for your project!
    │   ├── constitution-summary.md
    │   └── technical-context.md
    └── sessions/                # Per-session data (gitignored)
```

## Post-Install

1. **Customize** `.session/project-context/technical-context.md` with your stack, build/test commands
2. **Customize** `.session/project-context/constitution-summary.md` with quality standards
3. **Review** `AGENTS.md` for any project-specific additions

## Quick Start

```bash
# Development workflow (full 7-agent chain)
/session.start --issue 123

# Unstructured work
/session.start --goal "Fix performance bug"

# Experiment (no PR)
/session.start --experiment --goal "Test Redis caching"

# Quick question (no code)
/session.start --advisory --goal "How should I structure the API?"

# End session
/session.wrap
```

## Workflow Types

| Workflow | Agent Chain | Use Case |
|----------|-------------|----------|
| **Development** | start → plan → execute → validate → publish → finalize → wrap | Features, bug fixes |
| **Advisory** | start → wrap | Quick questions |
| **Experiment** | start → execute → wrap | Prototypes, spikes |

## Slash Commands

| Command | Purpose |
|---------|---------|
| `/session.start` | Initialize or resume a session |
| `/session.plan` | Generate task list |
| `/session.execute` | Execute tasks with TDD |
| `/session.validate` | Quality checks before PR |
| `/session.publish` | Create/update pull request |
| `/session.finalize` | Post-merge issue management |
| `/session.wrap` | Document and close session |

## Arguments

All agents support:
- `--comment "text"` - Provide specific instructions
- `--resume` - Continue from where you left off
- `--force` - Skip workflow validation (use with caution)

```bash
/session.execute --resume --comment "Continue from task 5"
```

## Session Continuity

If the CLI crashes or is killed mid-workflow, the next invocation detects this and guides you to resume:

```
⚠️ INTERRUPTED SESSION DETECTED
Previous session was interrupted during: validate

RECOMMENDED ACTION:
Run: /session.validate --resume
```

This prevents accidental data loss from skipped workflow steps.

## Updating

```bash
curl -sSL https://raw.githubusercontent.com/roperi/session-workflow/main/update.sh | bash
```

Preserves your `project-context/` customizations.

## Requirements

- Git repository
- GitHub Copilot CLI or compatible AI assistant
- Bash shell

## License

MIT

## Contributing

Contributions welcome! Please open an issue or PR.

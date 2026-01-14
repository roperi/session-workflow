# Session Workflow

A lightweight, portable session management system for AI-assisted development. Provides context continuity across AI sessions and structured work tracking.

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

## What It Does

When AI context windows reset, work continuity is lost. Session workflow solves this by:

1. **Tracking session state** - What's in progress, what's done
2. **Handoff notes** - Context for the next AI session
3. **Git hygiene** - Ensures clean state before session ends
4. **Project context** - Quick orientation for new sessions

## Usage

### Start a Session

```bash
# Work on a GitHub issue
/session.start --issue 123

# Unstructured work
/session.start --goal "Implement caching"

# Quick question (advisory mode)
/session.start --advisory --goal "How should I structure the API?"

# Experimental work
/session.start --experiment --goal "Test Redis performance"
```

### During Work

- Update `notes.md` with progress and decisions
- Update `tasks.md` as you complete tasks
- Commit code regularly

### End a Session

```bash
/session.wrap
```

## Session Types

| Type | Command | Use Case |
|------|---------|----------|
| **GitHub Issue** | `--issue 123` | Bugs, features with GitHub issues |
| **Unstructured** | `--goal "text"` | Ad-hoc work, maintenance |
| **Advisory** | `--advisory --goal` | Quick questions, no code changes |
| **Experiment** | `--experiment --goal` | Prototypes, investigations |

## Workflow Types

| Workflow | Agent Chain | Use Case |
|----------|-------------|----------|
| **Development** | start → plan → execute → validate → publish → finalize → wrap | Features, bug fixes |
| **Advisory** | start → wrap | Quick questions |
| **Experiment** | start → execute → wrap | Prototypes, spikes |

## File Structure

After installation:

```
your-repo/
├── .session/
│   ├── scripts/bash/        # Workflow scripts
│   ├── templates/           # Note templates
│   ├── docs/                # Documentation
│   ├── project-context/     # Your project's context (customize this!)
│   │   ├── constitution-summary.md
│   │   └── technical-context.md
│   └── sessions/            # Per-session data (gitignored)
└── .github/
    ├── agents/              # AI agent definitions
    │   └── session.*.agent.md
    └── prompts/             # Slash commands
        └── session.*.prompt.md
```

## Customization

After installation, customize these files for your project:

### `.session/project-context/constitution-summary.md`

Add your project's quality standards:
- Code style guidelines
- Testing requirements
- Documentation standards

### `.session/project-context/technical-context.md`

Add your project's technical details:
- Tech stack
- Project structure
- Development commands
- Key patterns

## Updating

To update to the latest version:

```bash
curl -sSL https://raw.githubusercontent.com/roperi/session-workflow/main/update.sh | bash
```

This updates scripts, agents, and prompts but preserves your `project-context/` customizations.

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

## Requirements

- Git repository
- GitHub Copilot CLI or compatible AI assistant
- Bash shell

## License

MIT

## Contributing

Contributions welcome! Please open an issue or PR.

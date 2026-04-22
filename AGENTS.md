# AGENTS.md

Repository map for AI coding agents.

**STOP**: If you are an AI agent, read **[AI.md](AI.md)** first for critical onboarding, build instructions, and architectural guardrails.

## Repository Index
```
session-workflow/
├── README.md                                   user-facing introduction, setup, and quick start
├── AI.md                                       AI-specific onboarding and context
├── AGENTS.md                                   repository map (index)
├── CHANGELOG.md                                version history
├── CONTRIBUTING.md                             contribution guidelines
├── install.sh                                  installation script
├── update.sh                                   update script
│
├── .github/
│   ├── CODEOWNERS                              code ownership definitions
│   ├── copilot-instructions.md                 repo-specific Copilot guidance
│   └── workflows/
│       └── tests.yml                           CI configuration
│
├── .maintainer/                                internal maintenance artifacts (private)
│
├── agents/                                     individual agent definitions (MD)
│
├── session/                                    session management logic and templates
│   ├── docs/                                   session workflow documentation
│   ├── scripts/                                bash execution scripts
│   │   └── bash/                               core bash utilities
│   │       ├── session-common.sh               shared constants and functions
│   │       └── lib/                            modular library functions
│   └── templates/                              session artifacts and notes templates
│
└── tests/                                      test suite execution
    └── run.sh                                  test runner
```

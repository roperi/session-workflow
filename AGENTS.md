# AGENTS.md

Repository map for AI coding agents. The structure is the index.

```
session-workflow/
├── README.md                                   user-facing introduction, setup, and quick start
├── AGENTS.md                                   repository map for AI coding agents
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

# Contributing to Session Workflow

Thank you for your interest in improving Session Workflow! This project is designed to help AI agents and humans maintain continuity across sessions.

## How to Contribute

1.  **Report Bugs**: Open an issue describing the bug and how to reproduce it.
2.  **Suggest Features**: Open an issue to discuss new features or improvements.
3.  **Pull Requests**:
    *   Fork the repository.
    *   Create a feature branch (`git checkout -b feature/amazing-feature`).
    *   Commit your changes (`git commit -m 'Add amazing feature'`).
    *   Push to the branch (`git push origin feature/amazing-feature`).
    *   Open a Pull Request.

## Development Setup

The project is primarily written in Bash. To set up your local environment:

1.  Install dependencies: `jq`, `shellcheck`.
2.  Run tests: `bash tests/run.sh`.

## Code Style

*   Follow `shellcheck` recommendations.
*   Ensure all new features include corresponding test cases in `tests/`.
*   Maintain the established directory structure and naming conventions.

## AI Agent Workflow

This project is optimized for AI-driven development. If you are using an AI agent to contribute, please refer to `session/docs/shared-workflow.md` for the internal agentic rules.

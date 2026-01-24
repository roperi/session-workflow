# Session Workflow Review Report

**Date:** 2026-01-24
**Reviewer:** Gemini CLI Agent

## Executive Summary

The `session-workflow` system provides a structured approach to AI-assisted development, using a chain of agents (`start` -> `plan` -> `execute` -> `validate` -> `publish` -> `finalize` -> `wrap`). The system is well-structured with a clear separation of concerns between agents and scripts for most stages. However, there is a significant inconsistency between the "mechanical" stages (start, wrap, etc.) which are script-backed, and the "creative" stages (plan, execute) which are purely prompt-driven. Additionally, there are opportunities to reduce prompt bloat and improve robustness by moving logic from prompts into shared shell scripts.

## 1. Structural Analysis

### 1.1 Agent vs. Script Asymmetry
*   **Observation:** The workflow uses a hybrid model:
    *   **Script-Backed:** `start`, `validate`, `publish`, `finalize`, `wrap` have corresponding bash scripts (`session-*.sh`). The agents mainly invoke these scripts.
    *   **Prompt-Driven:** `plan` and `execute` rely entirely on instructions within the `.prompt.md` files to execute bash commands, parse JSON, and manage files.
*   **Critique:** While `plan` and `execute` require AI creativity, the *setup* and *teardown* of these phases are mechanical. Relying on the LLM to "hallucinate" the correct bash commands to read context or create file skeletons increases token usage and the risk of error.
*   **Recommendation:** Introduce `session-plan.sh` and `session-execute.sh` to handle the deterministic parts of these tasks (e.g., loading context, validating prerequisites, creating file templates).

### 1.2 Missing Scripts
*   `session-plan.sh`: Missing. Logic for checking prerequisites and creating the initial `tasks.md` is embedded in `session.plan.prompt.md`.
*   `session-execute.sh`: Missing. Logic for checking workflow compatibility is embedded in `session.execute.prompt.md`.

## 2. Code & Prompt Analysis

### 2.1 Prompt Bloat & Fragility
*   **Issue:** `session.plan.prompt.md` contains a significant block of bash code to manually parse `.session/ACTIVE_SESSION`, check directories, and use `jq` to read `session-info.json`.
*   **Risk:** This is redundant and fragile. If the file structure changes, every prompt needs updating.
*   **Fix:** The prompts should leverage `session-common.sh` (or the proposed new scripts) to load this context standardly.
    *   *Bad:* Prompt contains `SESSION_ID=$(cat "$ACTIVE_SESSION_FILE") ... jq -r ...`
    *   *Good:* Prompt calls `source .session/scripts/bash/session-common.sh; get_active_session_context`

### 2.2 session-common.sh Utilization
*   **Inconsistency:**
    *   `session.execute.prompt.md` correctly sources `session-common.sh` to call `check_workflow_allowed`.
    *   `session.plan.prompt.md` *reinvents* the logic for reading session info instead of using common functions.
*   **State Management:**
    *   `session.common.agent.md` defines a strict "Workflow State Machine" with `set_workflow_step`.
    *   However, `session-start.sh` and `session-wrap.sh` implement their own state manipulation logic (writing/editing `state.json` directly) rather than strictly using the common state functions. This could lead to drift between the documented state machine and the actual implementation.

### 2.3 Implementation Gaps
*   **session-finalize.sh:** Contains several `TODO` comments indicating missing logic:
    *   `# TODO: Calculate and update parent issue progress`
    *   `# TODO: Update PR description with phase completion notes`
    *   `# TODO: Call sync script`
*   **session-validate.sh:** The validation logic is relatively basic. It checks for "tasks complete" by regex counting `[x]` vs `[ ]`. This is brittle if the `tasks.md` format varies slightly (e.g., nested lists).

## 3. Logic & Workflow Findings

### 3.1 Planning Logic
The `session.plan` agent is responsible for determining the session type (Speckit vs Issue vs Unstructured).
*   **Current:** The prompt instructs the AI to run `gh issue view` and `grep` for labels.
*   **Critique:** This logic is deterministic and should be in a script. `session-start.sh` *already* does some type detection. `session.plan` should trust the `type` field in `session-info.json` (created by `session.start`) rather than re-detecting it from GitHub.

### 3.2 Workflow Continuity
*   `session-common.sh` has a robust `check_interrupted_session` function.
*   **Gap:** It is unclear if `session.start` (the agent) proactively checks this before starting a *new* session logic, or if it relies entirely on the user providing the `--resume` flag. The prompt mentions it, but a script check would be safer to prevent overwriting active sessions.

## 4. Recommendations

1.  **Standardize Scripts:** Create `session-plan.sh` and `session-execute.sh` to handle context loading and validation.
2.  **Refactor Prompts:** Strip heavy bash logic from `session.plan.prompt.md` and `session.execute.prompt.md`. Replace with calls to the new scripts.
3.  **Unified State Management:** Refactor `session-start.sh` and `session-wrap.sh` to use the `set_workflow_step` function from `session-common.sh` instead of manual JSON manipulation. This ensures the "State Machine" is the single source of truth.
4.  **Implement Finalize TODOs:** Complete the missing logic in `session-finalize.sh` for parent issue updating and project syncing.
5.  **Trust `session-info.json`:** Ensure agents rely on the immutable `session-info.json` generated at start, rather than re-querying GitHub or re-deriving session types.

## 5. Conclusion
The codebase is solid but suffers from "logic leak" where implementation details have leaked into the AI prompts. Refactoring this logic back into the bash scripts will make the system more robust, token-efficient, and easier to maintain.

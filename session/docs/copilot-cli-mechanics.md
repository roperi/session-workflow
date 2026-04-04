# Copilot CLI Agent Mechanics

> How the GitHub Copilot CLI loads, invokes, and chains custom agents — and the constraints that shape session-workflow's design.

This document captures empirical findings from analyzing real Copilot CLI sessions via `events.jsonl` logs, combined with observed agent behavior across dozens of test runs. It is intended as a reference for anyone maintaining or extending session-workflow's agent chain.

## Table of Contents

- [Agent Loading](#agent-loading)
- [Primary vs Sub-Agent Distinction](#primary-vs-sub-agent-distinction)
- [The Task Tool and Sub-Agent Invocation](#the-task-tool-and-sub-agent-invocation)
- [Events File Analysis](#events-file-analysis)
- [Agent Chaining Patterns](#agent-chaining-patterns)
- [What Does NOT Work](#what-does-not-work)
- [The Orchestration Model](#the-orchestration-model)
- [Practical Constraints](#practical-constraints)
- [Debugging Tips](#debugging-tips)

---

## Agent Loading

### How Custom Agents Are Defined

Custom agents live in `.github/agents/{name}.agent.md`. The filename determines the agent name (e.g., `session.start.agent.md` → agent name `session.start`).

Corresponding `.github/prompts/{name}.prompt.md` files are symlinks for IDE prompt integration but are not used by the CLI.

### How the CLI Loads an Agent

When a user selects an agent (via the `/agent` command or `@.github/agents/` prefix), the CLI:

1. Reads the `.agent.md` file content
2. Injects it as **system instructions** for that conversation turn
3. The agent's markdown becomes the LLM's instruction set — it defines what the agent "knows" and how it behaves

**Key insight**: Agent instructions are injected **only at load time**. There is no mechanism to dynamically reload or swap agent instructions mid-conversation within the same agent context.

### User Invocation Methods

There are two ways to invoke a custom agent:

1. **`/agent` command** — User selects the agent from a menu, then types a prompt. The agent becomes the **primary agent** for that conversation.
2. **`@.github/agents/session.start.agent.md` prefix** — User types the agent file path as a mention. The outer Copilot agent wraps this in a task tool call, making the custom agent a **nested sub-agent**.

These two methods produce different nesting behavior (see next section).

---

## Primary vs Sub-Agent Distinction

This distinction is **critical** for understanding how agents appear in the CLI and how chaining works.

### Primary Agent (via `/agent` command)

- The agent's `.md` file is loaded as the **top-level system instructions**
- The agent's task tool calls create **top-level sub-agents** (separate bullet points in the CLI UI)
- The agent has full control of the conversation flow
- This is the **preferred invocation method** for session.start

**Example UI output (primary agent):**
```
● Session.start: Start session from issue #3
  └ Session initialized...

● Session.scope: Scope issue #3
  └ Scope defined...

● Session.spec: Write spec for issue #3
  └ Spec complete...
```

Each agent appears as a **top-level bullet** — this is the correct, expected behavior.

### Nested Sub-Agent (via `@` mention or outer task wrapper)

- The outer Copilot agent wraps the custom agent in a task tool call
- The custom agent becomes a **sub-agent** (nested bullet in UI)
- The custom agent's task tool calls create **sub-sub-agents** (further nested)
- All steps appear as sub-bullets of the outer agent

**Example UI output (nested agent):**
```
● Copilot: Invoking session.start
  ● Session.start: Start session from issue #3
    ● Session.scope: Scope issue #3
      └ Scope defined...
    ● Session.spec: Write spec for issue #3
      └ Spec complete...
```

Everything is nested under the outer agent — functionally equivalent but visually different.

### Why This Matters

The nesting level affects:
- **UI clarity** — Primary agents show clear step progression; nested agents look like one big operation
- **Context boundaries** — Each sub-agent gets its own context window with its agent instructions loaded fresh
- **Functionality** — Both approaches work correctly for state tracking and agent loading. The difference is primarily visual.

---

## The Task Tool and Sub-Agent Invocation

### How It Works

The Copilot CLI's `task` tool can invoke custom agents by setting `agent_type` to the agent name:

```
task(
  agent_type: "session.scope",
  prompt: "Scope issue #3. Session: 2026-03-11-3, dir: .session/sessions/2026-03/2026-03-11-3"
)
```

When the task tool receives an `agent_type` matching a `.github/agents/{agent_type}.agent.md` file:

1. The CLI loads the agent's `.md` file as system instructions for a new sub-agent context
2. The sub-agent runs with its own tools, context, and instructions
3. The sub-agent completes and returns results to the calling agent
4. The calling agent receives the results and continues

### Sub-Agent Context Isolation

Each sub-agent invocation:
- **Gets fresh context** — the sub-agent does not see the parent's conversation history
- **Loads its own agent instructions** — the `.agent.md` file is read and injected
- **Has its own tool access** — can run bash, read files, make API calls independently
- **Returns results** — output is passed back to the parent agent when complete

This isolation is what makes the orchestration model work: each step agent enforces its own scope boundaries because it loads its own instructions fresh.

### Prompt Design for Sub-Agents

The prompt passed to the task tool is the **only context** the sub-agent receives (besides its `.agent.md` instructions). It must include:

- **Issue number and title** — what we're working on
- **Session ID and directory** — where session artifacts live
- **Branch name** — the git branch for this session
- **Workflow and stage** — development/spike/maintenance/debug/operational, poc/mvp/production
- **Relevant artifact paths** — e.g., "Scope defined in {dir}/scope.md"
- **"Do NOT ask clarifying questions"** — prevents the sub-agent from returning without completing its work

**Bad prompt** (insufficient context):
```
"Do the scope step"
```

**Good prompt** (complete context):
```
"Scope issue #3: Add word count edge cases. Session: 2026-03-11-3, dir: .session/sessions/2026-03/2026-03-11-3, branch: fix/issue-3, workflow: development, stage: poc. Do NOT ask clarifying questions."
```

---

## Events File Analysis

### Location and Format

Copilot CLI session events are logged to:
```
~/.copilot/session-state/{session-uuid}/events.jsonl
```

Each line is a JSON object with at minimum a `type` field. Key event types:

### Event Types Reference

| Event Type | Key Fields | Meaning |
|-----------|-----------|---------|
| `user.message` | `transformedContent` | User's prompt (after agent mention expansion) |
| `tool.execution_start` | `toolName`, `arguments` | A tool was invoked (bash, task, grep, etc.) |
| `tool.execution_complete` | `toolName`, `result` | Tool returned results |
| `subagent.started` | `agentName` | A sub-agent was loaded and started |
| `subagent.completed` | `agentName` | A sub-agent finished successfully |
| `subagent.failed` | `agentName`, `error` | A sub-agent failed |
| `model.request` | `model` | LLM request was made |
| `model.response` | `model`, `content` | LLM response received |

### Identifying Agent Invocations

To verify an agent was properly loaded (not just its file read via `cat`):

1. Look for `tool.execution_start` with `toolName: "task"` and `arguments.agent_type: "session.scope"` (or similar)
2. This should be followed by `subagent.started` with `agentName: "session.scope"`
3. The sub-agent's work appears as nested tool calls
4. Finally, `subagent.completed` with `agentName: "session.scope"`

**Proper agent invocation sequence:**
```jsonl
{"type":"tool.execution_start","toolName":"task","arguments":{"agent_type":"session.scope","prompt":"..."}}
{"type":"subagent.started","agentName":"session.scope"}
{"type":"tool.execution_start","toolName":"bash","arguments":{"command":"session-preflight.sh..."}}
... (agent does its work) ...
{"type":"tool.execution_start","toolName":"bash","arguments":{"command":"session-postflight.sh..."}}
{"type":"subagent.completed","agentName":"session.scope"}
```

**Impersonation (agent reading another's file — no proper loading):**
```jsonl
{"type":"tool.execution_start","toolName":"bash","arguments":{"command":"cat .github/agents/session.scope.agent.md"}}
... (agent does scope work itself, no subagent events) ...
```

### Useful Analysis Commands

```bash
# Count events by type
jq -r '.type' events.jsonl | sort | uniq -c | sort -rn

# List all sub-agent invocations
jq -r 'select(.type == "subagent.started") | .agentName' events.jsonl

# Show the full chain of agent invocations
jq -r 'select(.type | startswith("subagent")) | "\(.type): \(.agentName)"' events.jsonl

# Find all task tool calls (agent invocations)
jq -r 'select(.type == "tool.execution_start" and .toolName == "task") | .arguments.agent_type' events.jsonl

# Extract user's original prompt
jq -r 'select(.type == "user.message") | .transformedContent' events.jsonl | head -5

# Find preflight/postflight calls
grep -o 'session-\(pre\|post\)flight[^"]*' events.jsonl | sort | uniq -c
```

---

## Agent Chaining Patterns

### What We Tried and Why

#### Pattern 1: Agent Self-Chaining ("Proceed now to session.X")

Each agent's handoff section said "Proceed now to session.X" — expecting the agent to invoke the next step.

**Result**: Agents would either:
- Skip the invocation and do the next step's work themselves (impersonation)
- Invoke the next agent but create deeply nested sub-sub-agents
- Invoke the next agent AND do its work (double execution)

**Verdict**: ❌ Unreliable. Agents don't consistently follow "invoke another agent" instructions.

#### Pattern 2: `cat`-Based Chain Execution

The orchestrator would `cat .github/agents/session.scope.agent.md` before each step, injecting the agent's instructions into the current context.

**Result**: The agent read the instructions and followed them, but:
- No separate context — all work happened in one agent's context
- No `subagent.started`/`subagent.completed` events (no proper agent loading)
- Steps appeared as sub-bullets of the parent (no visual separation)
- State tracking via preflight/postflight still worked (it's bash-based)

**Verdict**: ❌ Functionally works but bypasses proper agent loading. Not reliable long-term.

#### Pattern 3: Task Tool Invocation (Current Approach)

The orchestrator uses the task tool with `agent_type` to invoke each step as a proper sub-agent.

**Result**:
- Each agent loads its own `.agent.md` instructions ✅
- Each agent runs in its own context with proper isolation ✅
- `subagent.started`/`subagent.completed` events confirm proper loading ✅
- Preflight/postflight state tracking works ✅
- Steps appear as sub-bullets (UI limitation, not functional issue) ✅

**Verdict**: ✅ Correct approach. Each agent loads fresh, enforces its own boundaries.

### Sub-Agent Retry Behavior

Sub-agents sometimes return without completing their work (e.g., asking clarifying questions instead of proceeding). The orchestrator should:

1. Include "Do NOT ask clarifying questions" in every sub-agent prompt
2. Check if the step was actually completed (verify postflight ran)
3. If not completed, retry with a more explicit prompt

---

## What Does NOT Work

### Reading Agent Files Does NOT Load the Agent

```bash
cat .github/agents/session.scope.agent.md
```

This makes the text available in the current context, but:
- Does NOT create a new agent context
- Does NOT inject the text as system instructions
- Does NOT produce `subagent.started`/`subagent.completed` events
- The current agent may or may not follow the instructions it read

### Mid-Conversation Agent Swapping

There is no mechanism to "become" a different agent mid-conversation. The agent loaded at conversation start (or via task tool) is the agent for that context. You cannot:
- Reload agent instructions
- Switch to a different agent's identity
- Re-inject system instructions

### Expecting Agents to Follow Complex Multi-Step Handoff Instructions

Even with clear "invoke session.X next" instructions, agents frequently:
- Skip the invocation and do the work themselves
- Stop after their own work without invoking the next step
- Invoke the next agent AND also do its work (double execution)

This is why centralized orchestration from session.start is necessary.

---

## The Orchestration Model

### session.start as Sole Orchestrator

`session.start` is loaded as the primary agent and orchestrates the **entire** workflow chain:

```
session.start (orchestrator)
  ├── invokes session.scope (sub-agent)
  ├── invokes session.spec (sub-agent)
  ├── invokes session.plan (sub-agent)
  ├── invokes session.task (sub-agent)
  ├── invokes session.execute (sub-agent)
  ├── invokes session.validate (sub-agent)
  ├── invokes session.publish (sub-agent)
  ├── handles review cycle directly (no sub-agent)
  ├── invokes session.finalize (sub-agent)
  └── invokes session.wrap (sub-agent)
```

### Why Centralized?

1. **Reliability** — One agent controls the sequence; sub-agents can't skip or reorder steps
2. **No handoff failures** — Sub-agents return results; they don't need to know what comes next
3. **Context isolation** — Each sub-agent loads its own instructions fresh
4. **State tracking** — Preflight/postflight in each sub-agent ensures every step is recorded
5. **Matches proven pattern** — The user's original working prompt had session.start orchestrating all steps

### Sub-Agent Contract

Every sub-agent in the chain follows this contract:

1. Run preflight (`session-preflight.sh --step {name} --json`)
2. Do its scoped work (and ONLY its work)
3. Run postflight (`session-postflight.sh --step {name} --json`)
4. Return results to the orchestrator
5. ⛔ Do NOT invoke the next agent

---

## Practical Constraints

### Context Window Limits

Each sub-agent has its own context window. For long-running steps like `session.execute`, the agent may hit context limits. When this happens:
- The agent should wrap up gracefully (commit work, update state)
- The orchestrator can detect incomplete work and retry or resume

### Sub-Agent Display in UI

When session.start is invoked as a sub-agent itself (via `@` mention), all its sub-agents appear as nested sub-sub-bullets. This is a **platform limitation**:

```
● Copilot                          ← outer agent
  ● Session.start                  ← nested (because @-mentioned)
    ● Session.scope                ← sub-sub-agent
    ● Session.spec                 ← sub-sub-agent
```

When session.start is the **primary agent** (via `/agent`), sub-agents appear as top-level steps:

```
● Session.start                    ← primary agent
● Session.scope                    ← top-level sub-agent
● Session.spec                     ← top-level sub-agent
```

**Recommendation**: Use the `/agent` command to select session.start as the primary agent.

### Copilot Review vs Copilot Coding Agent

When requesting a code review on a PR:
- ✅ Use the `request_copilot_review` API/tool — triggers Copilot's review functionality
- ❌ Do NOT leave a comment mentioning `@copilot` — this triggers the Copilot **coding agent** (which creates commits), not the reviewer

---

## Debugging Tips

### Verifying Agent Loading

Check `events.jsonl` for the `subagent.started` → `subagent.completed` pattern:

```bash
SESSION_UUID="your-copilot-session-uuid"
EVENTS=~/.copilot/session-state/$SESSION_UUID/events.jsonl

# List all agent invocations in order
jq -r 'select(.type | startswith("subagent")) | "\(.type) \(.agentName)"' "$EVENTS"
```

### Verifying State Tracking

Check that each step has preflight AND postflight in the session's `state.json`:

```bash
SESSION_DIR=".session/sessions/2026-03/2026-03-11-3"
jq '.step_history[] | "\(.step): \(.status) (\(.started_at) → \(.ended_at))"' "$SESSION_DIR/state.json"
```

Every step should show `completed` (or `failed`) with both `started_at` and `ended_at` timestamps.

### Common Failure Modes

| Symptom | Cause | Fix |
|---------|-------|-----|
| Step missing from `step_history` | Agent skipped preflight/postflight | Check agent instructions have preflight+postflight |
| Step stuck at `in_progress` | Agent ran preflight but not postflight | Check if agent was interrupted or hit context limit |
| Step completed but wrong agent did the work | Agent impersonated another (read its file) | Ensure handoff says "return results" not "proceed to" |
| Sub-agent returned without completing | Agent asked clarifying questions | Add "Do NOT ask clarifying questions" to prompt |
| Same session overwritten | `session-start.sh` auto-resumed abandoned session | Use `--resume` explicitly; without it, script errors out |

---

## Appendix: Key File Locations

| File | Purpose |
|------|---------|
| `.github/agents/session.*.agent.md` | Agent instruction files |
| `.github/prompts/session.*.prompt.md` | IDE prompt integration (symlinks) |
| `.session/scripts/bash/session-preflight.sh` | Step entry guard (marks `in_progress`) |
| `.session/scripts/bash/session-postflight.sh` | Step exit guard (marks `completed`/`failed`) |
| `.session/sessions/{month}/{id}/state.json` | Local workflow bookkeeping with `step_history` (gitignored) |
| `.session/sessions/{month}/{id}/session-info.json` | Immutable session metadata |
| `~/.copilot/session-state/{uuid}/events.jsonl` | Copilot CLI event log |
| `session/docs/shared-workflow.md` | Universal workflow reference for all agents |

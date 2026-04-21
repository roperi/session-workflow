---
agent: session.retrospect
---

# Retrospective Analysis Prompt

## Objective
Perform a systematic retrospective analysis of the session.

## Data Sources
- Session Notes: `{session_dir}/notes.md`
- Session Next Steps: `{session_dir}/next.md`
- Session Tasks: `{session_dir}/tasks.md`
- Git History: run `git log --stat --decorate --oneline`

## Analysis Framework
1. **Metrics**: Calculate session duration, tasks completed, and churn rate.
2. **Successes**: Identify specific strategies that yielded positive outcomes.
3. **Friction**: Analyze barriers to completion or efficiency issues.
4. **Compounding**: Scan for technical solutions worth converting into `docs/solutions/`.
5. **Recommendations**: Propose specific workflow or config improvements.

## Report Format
- Use a markdown structure:
  - # Retrospective: {DATE}
  - ## Executive Summary
  - ## Key Metrics
  - ## Success Factors
  - ## Process Friction
  - ## Actionable Recommendations
  - ## Compoundable Solutions (if any)

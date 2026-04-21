# Retrospective Analysis Prompt

## Objective
Perform a systematic retrospective analysis of the session.

## Data Sources
- Git Log: `{session_dir}/../git-log.txt`
- Interaction Logs: `{session_dir}/../interaction.log`
- Session Tasks: `{session_dir}/tasks.md`

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

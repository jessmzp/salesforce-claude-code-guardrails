# Salesforce + Claude Code: AI-driven development with human approval gates

A practice project showing **AI-driven Salesforce development with Claude Code and human approval gates**. Claude writes and tests Apex, but a human approves the plan, reviews the code, and is the only one who deploys.

It is a standard Salesforce DX project (source API 64.0) developed against a single developer org, alias `practice`.

## How the guardrails fit together

| Layer           | Where                             | What it does                                      |
| --------------- | --------------------------------- | ------------------------------------------------- |
| Instructions    | `CLAUDE.md`                       | Tells Claude the rules to follow                  |
| Permissions     | `.claude/settings.json`           | Allows, prompts for, or forbids specific commands |
| Skill           | `.claude/skills/apex-test-class/` | Standardizes how Apex tests are written           |
| Subagent        | `.claude/agents/apex-reviewer.md` | Read-only code review after Apex changes          |
| PreToolUse hook | `.claude/hooks/block-deploy.sh`   | Hard-blocks deploy commands                       |
| Pre-commit hook | `.husky/pre-commit`               | Formats, lints, and tests before each commit      |

## CLAUDE.md rules

- Use only the `practice` org.
- **Standards:** one trigger per object with logic in a handler class; bulkified code (no SOQL/DML in loops); `with sharing` and `WITH USER_MODE`; tests that assert behavior and include a 200-record bulk test.
- **Workflow:** propose a plan and wait for approval before writing code; never run `sf project deploy start` (a human deploys after review); if a field or object isn't found, stop and ask.

## Permission rules

Defined in `.claude/settings.json`:

- **allow:** `sf project retrieve start`, `sf apex run test`, `sf project deploy validate`, `sf org display`
- **ask:** `sf project deploy start`, `deploy quick`, `deploy resume`
- **deny:** `sf org login`, `rm -rf`, and reading `.sf/`, `.sfdx/`, and `.env`

## Skill: `apex-test-class`

Used whenever a test class is created or updated. It requires a `@TestSetup` method, positive, negative, and 200-record bulk scenarios, `System.assertEquals` with clear messages (never coverage-only tests), and running the tests with the CLI to report results.

## Subagent: `apex-reviewer`

A read-only reviewer (tools: Read, Grep, Glob) that runs after Apex changes. It reports issues by severity, with file and line, for SOQL/DML in loops, missing `with sharing`, missing FLS/user mode, hardcoded IDs, and weak assertions. It never edits files.

## PreToolUse hook: deploy blocker

`.claude/hooks/block-deploy.sh` runs before every Bash tool call. If the command matches `sf project deploy (start|quick|resume)`, it exits with code 2 and tells Claude to use `deploy validate` instead.

## Pre-commit hook

Husky runs lint-staged on commit: Prettier (with the Apex and XML plugins) on staged files, ESLint on staged Aura/LWC JavaScript, and related LWC Jest tests with `--bail`. A failing test blocks the commit.

## MCP: Salesforce DX server

`.mcp.json` registers the Salesforce DX MCP server (`@salesforce/mcp`) with a least-privilege setup:

- **Only the `practice` org:** started with `--orgs practice`, so the server cannot reach any other authorized org.
- **Only the `orgs` and `data` toolsets:** `--toolsets orgs,data` exposes org info and SOQL queries, and nothing for metadata, Apex, or deployment.
- **Deny rule:** `mcp__salesforce-dx__resume_tool_operation` is in the `deny` list in `.claude/settings.json`, since resuming an operation could continue a long-running (for example deploy) job.

## Example: Closed Won onboarding trigger

When an Opportunity becomes Closed Won (on insert, or on update from not-won to won), three Tasks are created for the Opportunity owner, due in 1, 3, and 7 days:

1. Kickoff call with client
2. Send welcome package
3. Schedule onboarding session

The trigger checks `Opportunity.IsWon` rather than a hardcoded stage name, so it keeps working if the Closed Won stage is renamed or other won stages are added.

Files:

- `triggers/OpportunityTrigger.trigger`: delegates to the handler.
- `classes/OpportunityTriggerHandler.cls`: `with sharing`, bulkified, inserts Tasks in user mode.
- `classes/OpportunityTriggerHandlerTest.cls`: 6 tests:
  1. Update to Closed Won creates 3 tasks
  2. Insert as Closed Won creates 3 tasks
  3. Other stage changes create no tasks
  4. Re-saving a Closed Won Opportunity doesn't duplicate tasks
  5. Bulk: 200 Closed Won Opportunities create 600 tasks
  6. Tasks are assigned to the Opportunity owner, not the creator

## Commands

```bash
npm install                                                                    # tooling + husky
sf apex run test --test-level RunLocalTests --result-format human              # Apex tests
sf project deploy validate --source-dir force-app --test-level RunLocalTests   # validate only
```

Deployment itself is done by a human after review.

## Lessons learned

- **Deny rules apply in every mode.** `deny` rules in settings are enforced regardless of permission mode, so use them for anything that must never happen.
- **The deploy quick gap.** I found that `sf project deploy quick` could deploy a previously validated package without being covered by the original guardrails. It is now in the `ask` rules and in the hook's blocked patterns.
- **MCP tools don't go through the Bash hook.** The `block-deploy.sh` hook only matches `Bash` calls, so an MCP server can perform writes or deploys without it ever firing. Review every tool a server exposes and explicitly deny any write or deploy tool in `permissions.deny`.
- **String-matching hooks can be bypassed.** The hook matches command text, so aliases, wrapper scripts, or other tools could get around it. Treat hooks and permissions as safety nets, not security boundaries: **never give agents production credentials**. Keep them on a disposable developer org.

# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project overview

A Salesforce DX project (source format) generated from the standard `sf project generate` template. All metadata lives under `force-app/main/default/` in the conventional metadata-type folders (`classes`, `triggers`, `lwc`, `aura`, `objects`, `flexipages`, etc.). The `classes` and `triggers` folders now contain the Opportunity automation: `OpportunityTrigger` (trigger), `OpportunityTriggerHandler` (handler class) and `OpportunityTriggerHandlerTest` (its Apex test class); the other folders are still empty. Source API version is **64.0** (`sfdx-project.json`), with no namespace.

## Environment

- Two orgs are in use for the org-to-org migration practice:
  - `legacy`: the **source** org (simulates an acquired company).
  - `practice`: the **target** org and default org (developer org, set in `.sf/config.json`).
- You may read from both orgs (queries, retrieves, describes).
- Any write to either org (metadata deploy, data load, update or delete) must be done or approved by a human.
- Never use any other org.

## Commands

Install dev tooling first with `npm install` (also installs the husky pre-commit hook).

```bash
npm run lint                  # ESLint on Aura and LWC JavaScript only
npm test                      # LWC Jest unit tests (sfdx-lwc-jest)
npm run test:unit:watch
npm run test:unit:coverage
npx sfdx-lwc-jest -- force-app/main/default/lwc/myComponent   # tests for one component
npx sfdx-lwc-jest -- -t "test name"                           # single test by name
npm run prettier              # format Apex, LWC, Aura, XML, etc.
npm run prettier:verify
```

Salesforce CLI (`sf`) against the `practice` org:

```bash
sf project deploy validate --source-dir force-app --test-level RunLocalTests   # Validate
sf apex run test --test-level RunLocalTests --result-format human             # Tests
sf apex run test --tests FooTest --result-format human --synchronous          # one Apex test class
sf project retrieve start -m ApexClass:Foo
sf apex run -f scripts/apex/hello.apex      # anonymous Apex
sf data query -f scripts/soql/account.soql
```

## Standards

- One trigger per object; logic lives in a handler class.
- Bulkify: no SOQL or DML inside loops.
- Use `with sharing` and `WITH USER_MODE` in queries.
- Tests must assert behavior and include a 200-record bulk test.

## Workflow

- Propose a plan and wait for approval before writing code.
- Never run `sf project deploy start`. A human deploys after review.
- If a field or object is not found, stop and ask.

## Tooling notes

- **Pre-commit** (husky → lint-staged): runs Prettier on staged files, ESLint on staged Aura/LWC JS, and related LWC Jest tests with `--bail`. A failing LWC test blocks the commit.
- **Prettier** uses `prettier-plugin-apex` and `@prettier/plugin-xml`, `trailingComma: none`; LWC `.html` files use the `lwc` parser.
- **LWC Jest tests** go in each component's `__tests__/` folder (e.g. `lwc/myComponent/__tests__/myComponent.test.js`). `.forceignore` excludes `__tests__`, `jsconfig.json`, and `.eslintrc.json` from deployment.
- Apex is not unit-tested locally; Apex tests run in the org.

# Agents

This repository holds multiple sub-projects. Agents and contributors must follow clear, predictable rules to keep work safe, reviewable, and repeatable.

Core principles

- Use imperative mood in commit messages ("Add feature", "Fix bug").
- Write concise sentences and avoid idioms.
- Use ASD-STE100 Simplified Technical English for communication.
- Provide factual information only. No flattery or filler.
- When you disagree, explain why with evidence and a recommended alternative.

Repository structure and sub-projects

- The repo may contain multiple independent sub-projects (for example: `openSUSE/openQA/Helpers/openqa-job-settings`).
- Make changes inside the sub-project folder; avoid unrelated repository-wide edits unless necessary.
- Document non-obvious design decisions in REPORT.md inside the affected sub-project, or add an in-code comment if the decision is tightly scoped.

Commits and branches

- Keep commits small and focused. Each commit should do one thing.
- Commit message style: short imperative subject line, optional body with motivation and rationale. Example:

  Add Mojolicious test helper

  Add an inline Mojolicious::Lite test app for integration tests to avoid external servers.

- Include Co-authored-by trailer when an AI assistant contributed: `Co-authored-by: Copilot <223556219+Copilot@users.noreply.github.com>`.
- Branching for stacked changes:
  - Create a branch targeting the immediate base (e.g., `openqa-job-settings`) for parent changes.
  - Create dependent branches that base on the parent branch (e.g., `tests/mock-server-cli` based on `openqa-job-settings`) so PRs can be stacked in order.
  - For stacked PRs, open the parent PR first, then open the child PR with its base set to the parent branch.

Pull requests and reviews

- Open small, focused PRs. Include a clear PR body describing intent, files changed, test instructions, and any manual setup required.
- Use PR templates where available. Add a short checklist in the PR description for reviewers (e.g., run tests, verify CLI dry-run).
- For integration tests that require external services, provide a mock or an inline test server using the project framework (e.g., Mojolicious::Lite + Test::Mojo for Perl).

CI and testing

- Add CI workflows under `.github/workflows/` scoped to the sub-project path to avoid running unrelated jobs across the whole repo.
- Prefer reproducible containers for running tests during CI (the repo uses openSUSE for development but CI may run on Ubuntu; document any distro-specific steps).
- When a test requires system packages or language-specific packages, list them in the workflow and/or a docs file for local reproduction (README or REPORT.md).
- For tests that need a running service, prefer in-process test helpers (e.g., Test::Mojo) or start minimal servers in the test harness. Avoid relying on external network services in CI.
- For local reproduction that uses containers, prefer podman or docker; include a Makefile or small script under the sub-project to run tests inside a container.

Security and secrets

- Never commit secrets. CI secrets should be configured in the repository or organization settings and accessed through the workflow environment.
- If a test requires credentials, make the test skip by default and document how to provide credentials locally (environment variables or a local config file listed in .gitignore).
- Workflow files cannot be created or updated by an unscoped token when pushing from automation. If a push is rejected due to missing `workflow` scope, push the change using an account with the required permissions or create the workflow directly on the target repo.

Agent behavior and tooling

- Agents must make minimal, surgical changes and avoid touching unrelated code.
- Agents should validate changes by running the smallest targeted tests available. If tests require installing dependencies, document them and prefer listing dependencies in a sub-project manifest (cpanfile, requirements.txt, package.json).
- When using shell tools, avoid executing untrusted constructed commands. Do not use shell expansion constructs that dynamically build commands from variables or user-controlled input.

Testing and verification checklist for contributors

- Fetch and check out the target branch and any parent branches for stacked PRs.
- Run the sub-project test suite locally with the documented commands (for example: `cd openSUSE/openQA/Helpers/openqa-job-settings && prove -Ilib -I t/lib`).
- If a test fails due to missing system packages, reproduce the CI commands and add them to the sub-project README or the workflow.
- If making changes to tests, run them locally inside a container (podman or docker) to ensure environment parity with CI.

When to stop and ask

- If a task has multiple interpretations or design trade-offs that affect the API or test surface, stop and ask a focused question.
- If a change would require new infrastructure (e.g., a new CI runner with special permissions), stop and propose options rather than guessing.

Contact and audits

- Record all non-obvious decisions in REPORT.md within the affected sub-project.
- For security-sensitive changes, request a human review and do not merge until approval is obtained.

This document should evolve. Propose edits as PRs when workflows or conventions change.

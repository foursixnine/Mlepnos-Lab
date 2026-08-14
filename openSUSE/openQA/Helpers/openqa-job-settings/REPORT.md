# Report

Branch: openqa-job-settings

Added a minimal devcontainer for openSUSE Tumbleweed, a small JobGroups CLI command skeleton (bump) that subclasses OpenQA::CLI::api, tests with a fake OpenQA::Client, a Makefile to run tests, and usage notes in the project README.

Files added under openSUSE/openQA/Helpers/openqa-job-settings:
- bin/jobgroups-cli
- lib/JobGroups/Commands.pm
- lib/JobGroups/Command/bump.pm
- t/lib/OpenQA/Client.pm
- t/01-bump.t
- Makefile
- README.md

Repo-level additions:
- .devcontainer/devcontainer.json
- .devcontainer/Dockerfile
- AGENTS.md (bootstrapped)

Notes:
- The bump command defaults to dry-run. Use --no-dry-run --yes to apply writes.
- openQA client credentials are read via OpenQA::UserAgent (api => host) from client.conf or environment variables.
- This is a starting point and can be iterated, including adding proper dependency management and additional tests.

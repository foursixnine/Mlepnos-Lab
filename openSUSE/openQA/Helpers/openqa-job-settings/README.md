# openqa-job-settings

This small helper project provides a command to manage product settings between openQA instances.

Quickstart

- Open the repository in a Codespace or Copilot Space. The devcontainer uses openSUSE Tumbleweed.
- Open a terminal and run:

  cd openSUSE/openQA/Helpers/openqa-job-settings
  make test

- To run the CLI (dry-run):

  bin/jobgroups-cli bump --host http://source --target-host http://target --match VERSION=16.0 --set VERSION=16.1

To apply changes pass --no-dry-run --yes

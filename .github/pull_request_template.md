---
title: "tests: add Mojolicious mock server and basic bump integration test"

This PR adds a small Mojolicious-based mock server helper and a thin
integration test that runs the real CLI (jobgroups-cli bump) against the
mocked openQA API.

Files added on branch `tests/mock-server-cli` (base: `openqa-job-settings`):

- cpanfile
- openSUSE/openQA/Helpers/openqa-job-settings/t/lib/MockOpenQA.pm
- openSUSE/openQA/Helpers/openqa-job-settings/t/01-cli-basic.t

Notes:
- Tests use Mojo::JSON and Mojolicious only (no external JSON modules).
- Tests run the real CLI as a subprocess and point it to the mock server
  with --host and --target-host.
- The mock server implements minimal endpoints needed for the bump test
  (products, machines, test_suites, job_templates). It records requests
  and exposes them via GET /__requests for assertions.

How to run locally:

cd openSUSE/openQA/Helpers/openqa-job-settings
prove -Ilib -I t/lib


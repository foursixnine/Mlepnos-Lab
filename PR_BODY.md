PR: Add Mojolicious mock server and basic bump integration test

This branch adds a small Mojolicious mock server helper and a thin integration
test exercising the jobgroups-cli bump command.

Files added:
- cpanfile
- openSUSE/openQA/Helpers/openqa-job-settings/t/lib/MockOpenQA.pm
- openSUSE/openQA/Helpers/openqa-job-settings/t/01-cli-basic.t

Test strategy:
- Start the mock server from the test.
- Run the real CLI as a subprocess pointing to mock server.
- Use OpenQA::Client and Mojo::JSON to inspect the mock server state
  and assert the bump command updated product settings.

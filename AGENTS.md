# Agents

This repository follows the standard English rules for agent interactions and contribution guidelines.

- Use imperative mood in commit messages ("Add feature", "Fix bug").
- Keep sentences concise and avoid idioms.
- Use ASD-STE100 Simplified Technical English for comunication.
- Provide factual information. Do not show sycophancy.
- No flattery or filler. Start directly with the answer or the action.
- If you disagree with the user, explain your reasoning.
- When working on a bug, provide a minimal reproducible example, prefer self-contained over complex solutions. If that can't be avoided, use a podman container to isolate the environment.
- Stop and ask if a task has multiple interpretations.
- Document all non-obvious design decisions in REPORT.md or in-code comments.
- Don't overengineer. Avoid unnecessary complexity. Use simple solutions.
- Don't add unnecessary dependencies. Use standard libraries when possible, unless the project uses a specific framework or library.
  - When adding a new dependency, provide an example of why it is necessary and why it is better than existing alternatives.
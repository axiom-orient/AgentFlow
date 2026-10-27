# AgentFlow

Before changing this package or adapting a consumer, read [agent.me](agent.me),
then [docs/CONTRACT.md](docs/CONTRACT.md). The latter is the single behavioral
contract; source declarations define the public API.

- Keep one authoritative runtime in this repository. Consuming apps use a
  pinned remote Swift package; do not maintain app-specific runtime forks.
- Preserve public API and command lifetime semantics. Any break requires an
  explicit contract and version decision before editing consumers.
- Keep domain, state transitions, I/O, and presentation boundaries separate.
- Do not add TCA, architecture macros, global dependency lookup, app-specific
  models, host tools, or silent retry/fallback behavior.
- Use meaningful focused tests for runtime changes. Package tests do not
  establish an application's database, device, provider, or release readiness.
- Preserve existing work. Do not change CI/CD, GitHub Actions, workflows, or
  release automation without explicit current user authorization.

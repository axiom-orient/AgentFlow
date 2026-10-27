# AgentFlow

A small, dependency-free Swift MVI runtime with typed commands.

```text
Action → MainActor Store → pure Reducer → Command<Operation>
   ↑                                         ↓
   └──────── app runner + explicit ports ─────┘
```

AgentFlow owns observable value state and asynchronous command lifetime.
Applications own their domain, storage, providers, navigation and recovery.
It has no TCA dependency, macro system, global dependency container, workflow
engine, or host tooling.

## Install

```swift
dependencies: [
  .package(url: "https://github.com/axiom-orient/AgentFlow.git", exact: "0.1.1")
]
```

Add `.product(name: "AgentFlow", package: "AgentFlow")` to the target that
owns feature execution. A pure Domain target does not depend on AgentFlow.
Use the same resolved version throughout an app's dependency graph. Do not
also link a local AgentFlow copy.

Tools: Swift 6.2 or newer. Language mode: Swift 6. Deployment targets: iOS 17
and macOS 14. Apple observation uses the platform's Observation framework.
The runtime also has a non-Observation branch for non-Apple platforms; an
Apple-only test result does not qualify other platforms.

## Responsibilities

| Type | Responsibility |
|---|---|
| `Reducer<State, Action, Operation>` | Pure synchronous state transition and command planning |
| `Command<Operation>` | Typed work, cancellation or execution policy |
| `CommandRunner<Operation, Action, Values>` | App-owned execution with explicit dependencies |
| `Store<State, Action, Operation, Values>` | MainActor state, FIFO action turns and task lifetime |
| `Dependencies` | Sendable marker for concrete injected values |

The actual generic declarations and initializers are the public source API;
see [the execution contract](docs/CONTRACT.md). This table does not introduce
new wrapper types or a second effect system.

## Execution

Follow [the execution contract](docs/CONTRACT.md) for state ownership, child
composition, cancellation, result delivery and durable recovery. It is the
behavioral reference for this package and its consumers.

Observation tracks the Store's `state` property. A child read projection does
not automatically provide field-level observation. The package currently has
no scoped observation API; keep projections on the same state owner.

## Development

Start with [AGENTS.md](AGENTS.md) → [agent.me](agent.me) →
[the execution contract](docs/CONTRACT.md). The repository is
the runtime's authoritative source. [NOTICE.md](NOTICE.md) records provenance;
[LICENSE](LICENSE) applies to this package only.

Focused package tests cover task replacement, escaped sends, non-cooperative
cancellation, keyed work, teardown, draining and synchronous observation
reentry. Use continuation-controlled ordering rather than sleep-based retries.
Package compilation and these tests are separate from application, device,
database, provider and distribution qualification.

## Versioning

`0.1.0` is the first standalone package release. Published tags are immutable.
Consumers should pin an exact release and commit the actual resolved revision.
During the pre-1.0 period, an incompatible public contract requires a new minor
version and explicit migration notes. A patch must preserve public behavior.

`0.1.1` preserves the public API, encoding and execution behavior. It removes
a redundant delivery-key check, adds completion/key-reuse regressions and
clarifies observation, result delivery and task joining. No consumer source
migration is required; adopting this patch requires updating the exact pin
and its resolved revision together.

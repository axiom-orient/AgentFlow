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
  .package(url: "https://github.com/axiom-orient/AgentFlow.git", exact: "0.1.0")
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

Reducers do not start Tasks or perform I/O. Supply time, IDs and external
results as explicit values. Runners interpret operations with concrete app
ports. A child feature is value state plus mapped actions and operations;
it does not need its own task owner.

Store serializes synchronous reducer turns, including reentrant observation
callbacks. Effect completion order is unspecified. For replaceable
work, use a cancellation key and keep the current request/revision in feature
state. `Command.map` preserves keys, so consumers namespace keys for distinct
child instances.

Cancellation revokes result delivery and requests cooperative task cancellation.
It does not undo database commits or remote writes. Their durable identity,
receipts and uncertain outcomes remain the adapter's responsibility.

## Development

Start with [agent.me](agent.me) and [AGENTS.md](AGENTS.md). The repository is
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

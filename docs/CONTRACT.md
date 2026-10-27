# Execution contract

## Ownership and dependency direction

```text
UI → Feature → Domain
       ↓         ↑
     typed app ports
       ↓
Data / SDK / OS adapters

App composition selects the implementations and owns the root Store.
```

Domain contains values and deterministic rules. It does not import AgentFlow,
SwiftUI, SQL rows or provider models. Port contracts use values with explicit
meaning. An adapter DTO may carry storage or platform types when it stays
outside Domain; renaming it does not make it a domain value.

The Store's `state` setter is private. `send` enqueues actions and drains them
FIFO, with one reducer invocation at a time. Observation callbacks may enqueue
more actions without recursively mutating an active `inout State` access.
This is Store-local order. Arrival order from competing actors is not promised.

## Commands and runners

The reducer returns command values. It does not capture a repository or Store
inside an effect closure. `CommandRunner` supplies the execution boundary with
explicit Sendable dependencies. Its async `run` is `@concurrent`: this chooses
isolation, not a dedicated thread or permission to block a cooperative executor.

The runner is nonthrowing. A Feature defines expected failure/result actions;
the kernel does not flatten business errors into an automatic retry strategy.
Task cancellation is identified from task state, not merely from the dynamic
type of an error a dependency happened to throw.

| Execution policy, command, or Store method | Meaning |
|---|---|
| concurrent | Start independent work without replacing another key |
| cancel in flight | Revoke the old generation, request its cancellation, start replacement |
| drop if running | Keep the existing keyed operation; do not start the duplicate |
| cancel key | Revoke delivery and request cancellation for that key |
| `Store.cancelAll()` | Revoke and cancel all tasks owned by this Store |

Each execution has a monotonically increasing Store-local token. Late sends
check delivery authority. Completion removes a keyed registration only if it
still belongs to the completing task. An escaped send cannot mutate state
after its operation has finished or lost authority.

## Composition and lifetime

Compose child State/Action/Operation values in the parent reducer and map
commands. `Command.map` keeps execution policy and keys intact; cancellation
namespacing is the consumer's responsibility. Do not introduce another Store
for a projection of the same mutable state.

The Store owns task handles and cancels them at isolated deinitialization.
Task closures do not retain the Store indefinitely. `finish()` drains currently
owned work, including follow-up commands. It does not forcibly stop or join
non-cooperative work already revoked from the registry. Cancel unbounded streams
before finishing. `isRunning` is diagnostic, not observable UI loading state.

## Persistence and recovery

Runtime execution tokens do not replace a request ID, expected revision or
durable operation ID. A retry can have a new runtime token while preserving
the same save ID and receipt identity.

An adapter owns transaction boundaries, CAS, stored receipts and readback.
The runtime can reject a stale UI result after the external effect committed.
The next authoritative load must reconcile that effect; cancellation is not
rollback. Never convert an unknown write outcome into a new independent write.

Action/result delivery must not silently drop required transitions. A latest
snapshot observation stream has different buffering semantics from an action,
commit-result or receipt queue.

## Scope of evidence

Pure reducer tests establish transitions. Runtime tests establish the tested
task interleavings. Cross-compilation establishes source/toolchain compatibility
for that target. None of those proves an app's user flow, migration, model
quality, actual provider effect or App Store readiness.

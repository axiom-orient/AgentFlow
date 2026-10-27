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

One Feature defines value State, Action and Operation. Its pure synchronous
reducer has the shape `(inout State, Action) -> [Command<Operation>]`. Supply
time, randomness, IDs and external results as inputs; do not obtain them from
clocks, random generators or external systems inside the reducer. Do not
perform I/O, create tasks or mutate state outside the supplied State. `Sendable`
permits isolation crossing; it does not prove deep value semantics or reducer
purity. Keep independently mutable service/reference state in ports/adapters,
outside State snapshots. Consumers enforce these boundaries in their types,
target dependencies and tests.

The Store's `state` setter is private. `send` enqueues actions and drains them
FIFO, with one reducer invocation at a time. Observation callbacks may enqueue
more actions without recursively mutating an active `inout State` access.
This is Store-local order. Arrival order from competing actors is not promised.

## UI and observation

UI reads state and sends actions. View-local focus and animation state may stay
in the view; domain and workflow transitions stay in the Feature's reducer.
A facade must not become an independent state machine or task registry.

On Apple platforms, Observation tracks the single stored `state` property.
Reading `store.state.child` or a computed projection of that value still reads
that property. It does not create a field-level observation boundary. Runtime
bookkeeping is unobserved. Inout access can notify observers even when a
reducer leaves the value equal; this is not an equality-filtered state stream.
The synchronous FIFO queue protects reentrant Observation callbacks, which
may run before a mutation completes; callbacks should enqueue actions rather
than depend on seeing the resulting state at that moment.

There is no scoped observation API in this version. A future selector mechanism
needs a measured consumer problem and its own contract; do not add another
Store, mutable child model or snapshot-to-action buffer to simulate one.

## Commands and runners

The reducer returns command values. It does not capture a repository or Store
inside an effect closure. `CommandRunner` supplies the execution boundary with
explicit Sendable dependencies. Its async `run` is `@concurrent`: this chooses
isolation, not a dedicated thread or permission to block a cooperative executor.

The runner is nonthrowing. A Feature defines expected failure/result actions;
the kernel does not flatten business errors into an automatic retry strategy.
Task cancellation is identified from task state, not merely from the dynamic
type of an error a dependency happened to throw.

`Send` returns no receipt or delivery acknowledgement. The Store-provided Send
is tied to its execution token; a Send constructed by a caller has only the
behavior of that caller's closure. Neither form acknowledges a durable commit.

| Execution policy, command, or Store method | Meaning |
|---|---|
| concurrent | Start independent work without replacing another key |
| cancel in flight | Revoke the old generation, request its cancellation, start replacement |
| drop if running | Keep the existing keyed operation; do not start the duplicate |
| cancel key | Revoke delivery and request cancellation for that key |
| `Store.cancelAll()` | Revoke and cancel all tasks owned by this Store |

Policies control command execution after the action's state transition. A
dropped command does not undo or skip the reducer invocation. Features own
their loading, duplicate-request and cancellation state transitions.

Each execution has a monotonically increasing Store-local token. Late sends
check membership in the active task registry, the sole delivery authority.
Cancellation keys select active work; they are not another delivery authority.
Completion removes a keyed registration only if it still belongs to the
completing task. An escaped send cannot mutate state
after the Store has processed completion or revoked its token. Runners must
await required result sends and structured child work before returning. A
detached or escaped sender racing completion has no guaranteed ordering or
delivery. Optional progress relayed through unstructured tasks may be reordered
or omitted; required terminal results, commit outcomes and receipts must not
depend on that relay. The Feature must also reject progress that arrives after
its terminal transition.

## Composition and lifetime

Compose child State/Action/Operation values in the parent reducer and map
commands. `Command.map` keeps execution policy and keys intact; cancellation
namespacing is the consumer's responsibility. Keys are scoped to one Store,
not one operation type. Child work requiring independent lifetimes needs
distinct product/instance keys for both run and cancel commands. Sharing a key
intentionally shares its slot across operation types. Mapping operations alone
does not namespace keys. Separate Stores are for independent state owners,
not projections of the same mutable state.

This is not a single global Store requirement. Independent access, backup,
image, print or workspace features may own separate Stores when their state
and command lifetimes are independently authoritative.

The Store owns task handles and cancels them at isolated deinitialization.
Task closures do not retain the Store indefinitely. `finish()` selects an owned
task, awaits it, and repeats, including follow-up commands. Work revoked before
selection is not joined. If a selected task is revoked during that await,
`finish()` still waits for it to return. Cancellation of the caller does not
cancel Store tasks or interrupt the join. Cancel unbounded streams before
finishing. `isRunning` is diagnostic, not observable UI loading
state; cancellation does not reset a Feature's loading phase.

## Persistence and recovery

Runtime execution tokens do not replace a request ID, expected revision or
durable operation ID. A retry can have a new runtime token while preserving
the same save ID and receipt identity.

| Identity | Authority |
|---|---|
| Cancellation key | Selects a replaceable/droppable slot in one Store |
| Runtime token | Identifies one in-memory execution's delivery authority |
| Request ID / expected revision | Lets the Feature or adapter reject an obsolete result/write |
| Durable operation ID / receipt | Lets the adapter reconcile the same external effect across retries/restarts |

An adapter owns transaction boundaries, CAS, stored receipts and readback.
The runtime can reject a stale UI result after the external effect committed.
The next authoritative load must reconcile that effect; cancellation is not
rollback. Never convert an unknown write outcome into a new independent write.

Action/result delivery must not silently drop required transitions. A latest
snapshot observation stream has different buffering semantics from an action,
commit-result or receipt queue.

Conditional `Codable` conformances describe value encoding only. They do not
persist a task, establish a durable job queue or authorize replay of a command.

## Compatibility

The manifest requires Swift tools 6.2, Swift 6 language mode, iOS 17 and
macOS 14. `@concurrent` and isolated deinitialization are deliberate language
contracts. `NonisolatedNonsendingByDefault` is enabled for the runtime target;
do not infer runner isolation from an importing app's settings. No package-wide
MainActor default, newer observation stream or external dependency is required.
The non-Apple branch omits Observation and retains the same runtime logic.

## Scope of evidence

Pure reducer tests establish transitions. Runtime tests establish the tested
task interleavings. Cross-compilation establishes source/toolchain compatibility
for that target. None of those proves an app's user flow, migration, model
quality, actual provider effect or App Store readiness.

## Why use this Signal?

This module is aimed at projects where signals are part of the hot path and you want:

- **Low `Fire` overhead**: spawn/defer modes use a cached “runner” coroutine so yield-safe handlers don’t require creating a fresh coroutine per handler call.
- **Cheap disconnects**: `Connection:Disconnect()` is **O(1)** via a doubly-linked list.
- **Allocation-friendly behavior**: handler nodes are pooled to reduce GC churn.
- **Re-entrancy safety**: disconnecting (or disconnect-all) during `Fire` won’t corrupt iteration; recycling is deferred until all nested `Fire` calls finish.

## When should you use it?

- **Your handlers may yield** and you still want performance: use `Signal.new("spawn")` (default) or `Signal.new("defer")`.
- **You connect/disconnect frequently** (subscriptions churn).
- **You need priority ordering sometimes** (e.g., internal systems first, user hooks later).

## When should you not use it?

- **You want the smallest possible implementation** and performance doesn’t matter.
- **You use priorities heavily and have very large handler lists**: `ConnectWithPriority` can become O(n) due to sorted insertion. (Whether this matters depends on your workload.)

## Mode selection quick guide

- **`"sync"`**: fastest dispatch, but **not yield-safe** (a yielding handler yields the caller).
- **`"defer"`**: handlers scheduled via `task.defer` (yield-safe).
- **`"spawn"`**: handlers scheduled via `task.spawn` (yield-safe, default).

See [`SignalAPI.md`](SignalAPI.md) for full behavior and signatures.

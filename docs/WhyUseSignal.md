## Why use this Signal?

This module is aimed at projects where signals are part of the hot path and you want:

- **Low `Fire` overhead**: `Fire` schedules handlers via a cached “runner” coroutine so yield-safe handlers don’t require creating a fresh coroutine per handler call.
- **Cheap disconnects**: `Connection:Disconnect()` is **O(1)** via a doubly-linked list.
- **Allocation-friendly behavior**: handler nodes are pooled to reduce GC churn.
- **Re-entrancy safety**: disconnecting (or disconnect-all) during `Fire` won’t corrupt iteration; recycling is deferred until all nested `Fire` calls finish.

## When should you use it?

- **Your handlers may yield** and you still want performance: `Signal.new()` schedules handlers with `task.spawn` using a cached runner coroutine.
- **You connect/disconnect frequently** (subscriptions churn).

See [`SignalAPI.md`](SignalAPI.md) for full behavior and signatures.

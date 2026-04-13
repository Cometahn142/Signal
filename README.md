# Signal

High-performance Luau `Signal` with:
- Fast `Fire` hot path (runner coroutine cache for yield-safe handlers)
- O(1) `Disconnect`
- Node pooling + safe re-entrancy during `Fire`

See `examples/quickstart.luau` for a couple usage snippets.

## Docs

- [`docs/WhyUseSignal.md`](docs/WhyUseSignal.md)
- [`docs/SignalAPI.md`](docs/SignalAPI.md)

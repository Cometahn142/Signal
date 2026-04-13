--!strict

--[=[

Quick start:

```lua
local Signal = require(path.to.Signal)
local sig = Signal.new() -- default: "spawn"

sig:Connect(function(v)
	print(v) -- 123
end)

sig:Fire(123)
```
]=]

--[=[
Public API types
]=]

export type Connection = {
	-- Disconnects this connection. Safe to call multiple times.
	Disconnect: (self: Connection) -> (),
	-- True while the connection is active (i.e. will be fired).
	Connected: boolean,
}

export type FireMode = "sync" | "defer" | "spawn"

export type Signal<T...> = {
	-- Connect a handler. Higher priority runs earlier; omit/0 for fastest connect path.
	Connect: (self: Signal<T...>, fn: (T...) -> (), priority: number?) -> Connection,
	-- Same as Connect, but priority is required and comes first.
	ConnectWithPriority: (self: Signal<T...>, priority: number, fn: (T...) -> ()) -> Connection,
	-- Connect a handler that auto-disconnects after one fire.
	Once: (self: Signal<T...>, fn: (T...) -> (), priority: number?) -> Connection,
	-- Yield until the next Fire and return its arguments.
	Wait: (self: Signal<T...>) -> T...,
	-- Yield until the next Fire or until timeout seconds elapse.
	-- Returns (true, ...) when fired; returns (false) on timeout.
	WaitTimeout: (self: Signal<T...>, timeout: number) -> (boolean, T...),
	-- Fire the signal using the instance's configured mode.
	Fire: (self: Signal<T...>, T...) -> (),
	-- Fire synchronously (handlers run immediately on the current thread).
	FireSync: (self: Signal<T...>, T...) -> (),
	-- Fire deferred (handlers scheduled via task.defer).
	FireDeferred: (self: Signal<T...>, T...) -> (),
	-- Fire spawned (handlers scheduled via task.spawn).
	FireSpawn: (self: Signal<T...>, T...) -> (),
	-- Disconnect all connections.
	DisconnectAll: (self: Signal<T...>) -> (),
	-- Number of active connections.
	GetConnectionCount: (self: Signal<T...>) -> number,
	-- True if there is at least one active connection.
	HasConnections: (self: Signal<T...>) -> boolean,
	-- Disconnect all and permanently mark as destroyed.
	Destroy: (self: Signal<T...>) -> (),
}

--[=[
Internal structural types
]=]

type Node<T...> = {
	-- Listener function to invoke.
	fn: (T...) -> (),
	-- Linked-list pointer used ONLY for handler iteration and ordering.
	next: Node<T...>?,
	-- Doubly-linked list back pointer for O(1) disconnect.
	prev: Node<T...>?,
	-- Free-list pointer used ONLY for pooling/trash (never used for handler iteration).
	freeNext: Node<T...>?,
	-- Cached connection state for the Fire hot path.
	-- We keep the public `Connection.Connected` flag too, but Fire reads this boolean
	-- directly to avoid following pointers into the connection object.
	connected: boolean,
	-- If true, this listener disconnects itself after it runs once.
	once: boolean,
	-- Public-facing connection object.
	conn: _Connection<T...>,
	-- Higher runs earlier; 0 is the fast-path "no ordering needed" case.
	priority: number,
	-- Owning signal while connected; nil once disconnected/recycled.
	owner: _Signal<T...>?,
}

type _Signal<T...> = Signal<T...> & {
	-- Head/tail of the active handler list.
	_head: Node<T...>?,
	_tail: Node<T...>?,
	-- Pooled (reusable) nodes.
	_pool: Node<T...>?,
	-- Nodes unlinked during Fire; recycled once all nested Fire calls finish.
	_trash: Node<T...>?,
	_count: number,
	-- Once destroyed, all methods error via assertAlive.
	_destroyed: boolean,
	_mode: FireMode,
	-- Fire dispatch is fixed at construction time (no mode checks inside Fire()).
	_fire: (self: _Signal<T...>, T...) -> (),
	-- Re-entrancy guard used to delay recycling during nested Fire calls.
	_firing: number,
	-- Number of active non-zero-priority connections (enables O(1) head insert fast path
	-- when it reaches 0).
	_prioCount: number,
}

type _Connection<T...> = Connection & {
	-- Back-pointer to the node for O(1) unlink.
	_node: Node<T...>?,
	-- Back-pointer to the owning signal for O(1) unlink.
	_signal: _Signal<T...>?,
}

-- Used to clear function references when recycling nodes (avoid allocating new closures).
local def = function() end

-- Set to true for safer error surfacing at slight overhead.
local DEBUG = false

-- GoodSignal-style cached runner coroutine used for spawn/defer modes.
local freeRunnerThread: thread? = nil

local acquireRunnerThreadAndCallEventHandler: ((...any) -> (), ...any) -> ()
if DEBUG then
	-- Debug mode: protect the handler call so runner state is restored even if it errors.
	acquireRunnerThreadAndCallEventHandler = function(fn, ...)
		-- We temporarily clear the free runner while it is "in use".
		local acquiredRunnerThread = freeRunnerThread
		freeRunnerThread = nil
		local packed = table.pack(pcall(fn, ...))
		local ok = packed[1]
		local err = packed[2]
		-- Always restore runner state before propagating errors.
		freeRunnerThread = acquiredRunnerThread
		if not ok then
			error(err, 0)
		end
	end
else
	-- Fast mode: minimal overhead; errors will abort the runner coroutine.
	acquireRunnerThreadAndCallEventHandler = function(fn, ...)
		local acquiredRunnerThread = freeRunnerThread
		freeRunnerThread = nil
		fn(...)
		freeRunnerThread = acquiredRunnerThread
	end
end

local function runEventHandlerInFreeThread()
	-- The runner is resumed with (fn, ...). We intentionally yield first to avoid
	-- keeping "..." references on the runner stack between invocations.
	while true do
		acquireRunnerThreadAndCallEventHandler(coroutine.yield())
	end
end

--[=[
Runner coroutine cache (spawn/defer)

This matters when handlers yield. With "spawn"/"defer", handlers run on a cached runner
coroutine, which avoids creating a new coroutine per handler call.

```lua
local Signal = require(path.to.Signal)
local s = Signal.new("spawn")

s:Connect(function()
	task.wait(0.05)
	print("yielded")
end)

s:Fire()
```
]=]
local function ensureFreeRunnerThread(): thread
	local t = freeRunnerThread
	if t then
		return t
	end
	local created = coroutine.create(runEventHandlerInFreeThread)
	if DEBUG then
		-- Debug mode: detect runner creation/resume issues eagerly.
		local ok, err = coroutine.resume(created)
		if not ok then
			error(err, 0)
		end
	else
		coroutine.resume(created)
	end
	freeRunnerThread = created
	return created
end

--[=[
Core invariants & pooling
]=]

local function assertAlive<T...>(signal: _Signal<T...>)
	if signal._destroyed then
		error("Signal is destroyed", 3)
	end
end

--[=[
Re-entrancy safety (trash list)

During `Fire`, handlers may disconnect themselves or others. We avoid recycling nodes
immediately while any Fire loop is active, so iteration never observes a recycled node.

```lua
local Signal = require(path.to.Signal)
local s = Signal.new("sync")

local c
c = s:Connect(function()
	c:Disconnect() -- disconnect during Fire
end)

s:Fire() -- safe
```
]=]
local function pushTrash<T...>(signal: _Signal<T...>, node: Node<T...>)
	-- Node is already unlinked from the handler list.
	-- During Fire we must not recycle immediately to avoid reusing the node while an
	-- outer Fire loop might still be holding references.
	node.fn = def :: any
	node.once = false
	node.conn = nil :: any
	node.priority = 0
	node.owner = nil
	local nxt = signal._trash
	node.freeNext = nxt
	signal._trash = node
end

--[=[
`next` vs `freeNext`

`node.next` is only for iterating connected handlers.
`node.freeNext` is only for pooling/trash lists.
Keeping them separate prevents Fire iteration from being corrupted by pooling.
]=]
local function recycleNode<T...>(signal: _Signal<T...>, node: Node<T...>)
	-- Clear all handler-list pointers so pooled nodes never remain linked.
	node.fn = def :: any
	node.once = false
	node.conn = nil :: any
	node.priority = 0
	node.owner = nil
	node.prev = nil
	node.next = nil
	node.freeNext = signal._pool
	signal._pool = node
end

local function asSignal<T...>(self: Signal<T...>): _Signal<T...>
	return (self :: any) :: _Signal<T...>
end

local function acquireNode<T...>(signal: _Signal<T...>): Node<T...>
	-- Pop from pool if available; otherwise allocate a fresh table.
	local node = signal._pool
	if node then
		signal._pool = node.freeNext
		node.freeNext = nil
		return node
	end
	local fresh = {} :: any
	fresh.fn = def
	fresh.next = nil
	fresh.prev = nil
	fresh.freeNext = nil
	fresh.connected = false
	fresh.once = false
	fresh.conn = nil
	fresh.priority = 0
	fresh.owner = nil
	return fresh :: Node<T...>
end

local function insertNode<T...>(signal: _Signal<T...>, node: Node<T...>)
	-- Fast path: if there are no active priorities and this node has priority 0,
	-- we can just push to the head (O(1)).

	if node.priority == 0 and signal._prioCount == 0 then
		local head = signal._head
		if head then
			node.next = head
			head.prev = node
			signal._head = node
			signal._count += 1
		else
			signal._head = node
			signal._tail = node
			signal._count = 1
		end
		return
	end

	local head = signal._head
	if not head then
		signal._head = node
		signal._tail = node
		signal._count = 1
		return
	end

	local pr = node.priority
	if pr > head.priority then
		node.next = head
		head.prev = node
		signal._head = node
		signal._count += 1
		return
	end

	local tail = signal._tail :: Node<T...>
	if pr <= tail.priority then
		tail.next = node
		node.prev = tail
		signal._tail = node
		signal._count += 1
		return
	end

	local cur = head
	while cur do
		local nxt = cur.next
		if not nxt then
			cur.next = node
			node.prev = cur
			signal._tail = node
			signal._count += 1
			return
		end
		if pr > nxt.priority then
			node.next = nxt
			node.prev = cur
			cur.next = node
			nxt.prev = node
			signal._count += 1
			return
		end
		cur = nxt
	end
end

local Connection = {}
Connection.__index = Connection

function Connection.new<T...>(signal: _Signal<T...>, node: Node<T...>): _Connection<T...>
	-- Connection objects are public-facing handles and remain stable even though
	-- their underlying nodes are pooled/reused.
	local raw = setmetatable({}, Connection) :: any
	raw.Connected = true
	raw._signal = signal
	raw._node = node
	return raw :: _Connection<T...>
end

--[=[
Unlink + recycle (internal)

This is the single place that unhooks a node from the active list and moves it into
trash/pool. `Connection:Disconnect()` and `Once` both route through this to keep
behavior consistent and O(1).
]=]
local function disconnectNode<T...>(signal: _Signal<T...>, node: Node<T...>)
	-- Internal unlink + recycle. This is used both by Connection:Disconnect() and by
	-- the Fire path for Once connections (to avoid extra indirection).
	local conn = node.conn
	conn.Connected = false
	conn._node = nil
	conn._signal = nil

	local pr = node.priority
	local prev = node.prev
	local next = node.next
	if prev then
		prev.next = next
	else
		signal._head = next
	end
	if next then
		next.prev = prev
	else
		signal._tail = prev
	end

	node.owner = nil
	node.connected = false
	signal._count -= 1
	if pr ~= 0 then
		signal._prioCount -= 1
	end

	if signal._firing > 0 then
		pushTrash(signal, node)
	else
		recycleNode(signal, node)
	end
end

function Connection:Disconnect()
	-- Public disconnect: O(1) and safe to call repeatedly.
	local conn = self :: _Connection<any>
	if not conn.Connected then
		return
	end
	conn.Connected = false

	local node = conn._node
	local signal = conn._signal
	-- Break back-references early to prevent repeat work and reduce retention.
	conn._node = nil
	conn._signal = nil
	if not node or not signal then
		return
	end
	if node.owner ~= signal then
		return
	end
	node.connected = false
	disconnectNode(signal, node)
end

local Signal = {}
Signal.__index = Signal

local function connectInternal<T...>(signal: _Signal<T...>, fn: (T...) -> (), once: boolean, priority: number): Connection
	assertAlive(signal)
	local node = acquireNode(signal)
	node.fn = fn
	node.connected = true
	node.once = once
	node.priority = priority
	node.prev = nil
	node.next = nil
	node.freeNext = nil
	node.owner = signal
	if priority ~= 0 then
		-- Track whether we can use the O(1) head-insert fast path.
		signal._prioCount += 1
	end

	local conn = Connection.new(signal, node)
	node.conn = conn

	insertNode(signal, node)
	return conn
end

-- Fire dispatch:
-- - sync: inline (fastest, not yield-safe)
-- - defer/spawn: scheduled (yield-safe via runner cache)
local function fireSync<T...>(signal: _Signal<T...>, ...: T...)
	-- Synchronous dispatch: calls handlers inline on the current thread.
	assertAlive(signal)
	signal._firing += 1
	local cur = signal._head
	while cur do
		local nxt = cur.next
		if cur.connected then
			cur.fn(...)
			if cur.once then
				disconnectNode(signal, cur)
			end
		end
		cur = nxt
	end
	signal._firing -= 1
	if signal._firing == 0 then
		-- Flush any nodes unlinked during the fire.
		local t = signal._trash
		signal._trash = nil
		while t do
			local nxt = t.freeNext
			t.freeNext = nil
			recycleNode(signal, t)
			t = nxt
		end
	end
end

local function fireDefer<T...>(signal: _Signal<T...>, ...: T...)
	-- Deferred dispatch: schedules handlers via task.defer with a cached runner thread.
	assertAlive(signal)
	signal._firing += 1
	local runner = ensureFreeRunnerThread()
	local taskDefer = task.defer
	local cur = signal._head
	while cur do
		local nxt = cur.next
		if cur.connected then
			taskDefer(runner, cur.fn, ...)
			if cur.once then
				disconnectNode(signal, cur)
			end
		end
		cur = nxt
	end
	signal._firing -= 1
	if signal._firing == 0 then
		local t = signal._trash
		signal._trash = nil
		while t do
			local nxt = t.freeNext
			t.freeNext = nil
			recycleNode(signal, t)
			t = nxt
		end
	end
end

local function fireSpawn<T...>(signal: _Signal<T...>, ...: T...)
	-- Spawn dispatch: schedules handlers via task.spawn with a cached runner thread.
	assertAlive(signal)
	signal._firing += 1
	local runner = ensureFreeRunnerThread()
	local taskSpawn = task.spawn
	local cur = signal._head
	while cur do
		local nxt = cur.next
		if cur.connected then
			taskSpawn(runner, cur.fn, ...)
			if cur.once then
				disconnectNode(signal, cur)
			end
		end
		cur = nxt
	end
	signal._firing -= 1
	if signal._firing == 0 then
		local t = signal._trash
		signal._trash = nil
		while t do
			local nxt = t.freeNext
			t.freeNext = nil
			recycleNode(signal, t)
			t = nxt
		end
	end
end

function Signal.new<T...>(mode: FireMode?): Signal<T...>
	-- Construct a new signal. The mode selects how handlers are executed.
	-- Note: "sync" is fastest but not yield-safe (a yielding handler will yield the caller).
	local self = setmetatable({}, Signal) :: any
	local s = (self :: any) :: _Signal<T...>
	s._head = nil
	s._tail = nil
	s._pool = nil
	s._trash = nil
	s._count = 0
	s._destroyed = false
	s._mode = mode or "spawn"
	if s._mode == "sync" then
		s._fire = fireSync
	elseif s._mode == "defer" then
		s._fire = fireDefer
	else
		s._fire = fireSpawn
	end
	s._firing = 0
	s._prioCount = 0
	return self
end

function Signal:Connect<T...>(fn: (T...) -> (), priority: number?): Connection
	-- Fastest path: omit priority (or use 0) to keep Connect O(1) while no other
	-- non-zero priorities are active.
	local s = asSignal(self)
	return connectInternal(s, fn, false, priority or 0)
end

--[=[
Priority ordering

Higher priority runs earlier. Use priorities only when order matters, since it may make
Connect O(n) due to sorted insertion.

```lua
local Signal = require(path.to.Signal)
local s = Signal.new("sync")

s:Connect(function() print("prio 0") end)
s:ConnectWithPriority(10, function() print("prio 10 first") end)

s:Fire()
```
]=]
function Signal:ConnectWithPriority<T...>(priority: number, fn: (T...) -> ()): Connection
	-- Explicit-priority connect (may become O(n) due to sorted insertion).
	local s = asSignal(self)
	return connectInternal(s, fn, false, priority)
end

function Signal:Once<T...>(fn: (T...) -> (), priority: number?): Connection
	-- One-shot connect: auto-disconnect after the handler runs once.
	local s = asSignal(self)
	return connectInternal(s, fn, true, priority or 0)
end

function Signal:Wait<T...>(): T...
	-- Wait is implemented via a temporary Once connection that resumes the current coroutine.
	local thread = coroutine.running()

	self:Once(function(...)
		task.spawn(thread, ...)
	end)

	return coroutine.yield()
end

--[=[
WaitTimeout

Returns `true, ...` if the signal fires before the timeout, otherwise `false`.

```lua
local Signal = require(path.to.Signal)
local s = Signal.new()

task.spawn(function()
	local ok, value = s:WaitTimeout(0.05)
	print("ok?", ok, value)
end)
```
]=]
function Signal:WaitTimeout<T...>(timeout: number): (boolean, T...)
	-- Like Wait(), but disconnects and returns false after timeout seconds.

	local thread = coroutine.running()
	local done = false

	local conn = self:Once(function(...)
		if done then
			return
		end
		done = true
		task.spawn(thread, true, ...)
	end)

	task.delay(timeout, function()
		if done then
			return
		end
		done = true
		conn:Disconnect()
		task.spawn(thread, false)
	end)

	local yielded = table.pack(coroutine.yield())
	local ok = yielded[1]
	if ok == true then
		return true, (table.unpack(yielded, 2, yielded.n) :: any)
	end
	return false
end

function Signal:Fire<T...>(...: T...)
	-- Fire via the mode-selected dispatch function (fixed at construction time).

	local s = asSignal(self)
	s._fire(s, ...)
end

function Signal:FireSync<T...>(...: T...)
	-- Convenience: force sync dispatch regardless of the configured mode.
	local s = asSignal(self)
	fireSync(s, ...)
end

function Signal:FireDeferred<T...>(...: T...)
	-- Convenience: force defer dispatch regardless of the configured mode.
	local s = asSignal(self)
	fireDefer(s, ...)
end

function Signal:FireSpawn<T...>(...: T...)
	-- Convenience: force spawn dispatch regardless of the configured mode.
	local s = asSignal(self)
	fireSpawn(s, ...)
end

function Signal:DisconnectAll<T...>()
	-- Disconnect all listeners. We first detach the active list, then recycle nodes.
	-- During Fire, nodes go to trash and are recycled when the last nested Fire finishes.

	local s = asSignal(self)
	assertAlive(s)
	local cur = s._head
	s._head = nil
	s._tail = nil
	s._count = 0
	s._prioCount = 0
	while cur do
		local nxt = cur.next
		cur.connected = false
		cur.conn.Connected = false
		cur.owner = nil
		cur.conn._node = nil
		cur.conn._signal = nil
		if s._firing > 0 then
			pushTrash(s, cur)
		else
			recycleNode(s, cur)
		end
		cur = nxt
	end
end

function Signal:GetConnectionCount<T...>(): number
	-- O(1) current connection count.
	local s = asSignal(self)
	return s._count
end

function Signal:HasConnections<T...>(): boolean
	-- O(1) emptiness check.
	local s = asSignal(self)
	return s._count > 0
end

--[=[
Destroy

Disconnects all handlers and permanently marks the signal as destroyed.
Any later method call errors via `assertAlive`.

```lua
local Signal = require(path.to.Signal)
local s = Signal.new()

s:Destroy()
-- s:Fire() -- errors
```
]=]
function Signal:Destroy<T...>()
	-- Permanently disable this signal. After this, any method call errors via assertAlive.

	local s = asSignal(self)
	if s._destroyed then
		return
	end
	self:DisconnectAll()
	s._destroyed = true
	s._pool = nil
	s._trash = nil
	s._prioCount = 0
end

return Signal

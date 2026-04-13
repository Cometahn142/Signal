--!strict

export type Connection = {
	Disconnect: (self: Connection) -> (),
	Connected: boolean,
}

export type FireMode = "sync" | "defer" | "spawn"

export type Signal<T...> = {
	Connect: (self: Signal<T...>, fn: (T...) -> (), priority: number?) -> Connection,
	ConnectWithPriority: (self: Signal<T...>, priority: number, fn: (T...) -> ()) -> Connection,
	Once: (self: Signal<T...>, fn: (T...) -> (), priority: number?) -> Connection,
	Wait: (self: Signal<T...>) -> T...,
	WaitTimeout: (self: Signal<T...>, timeout: number) -> (boolean, T...),
	Fire: (self: Signal<T...>, T...) -> (),
	FireSync: (self: Signal<T...>, T...) -> (),
	FireDeferred: (self: Signal<T...>, T...) -> (),
	FireSpawn: (self: Signal<T...>, T...) -> (),
	DisconnectAll: (self: Signal<T...>) -> (),
	GetConnectionCount: (self: Signal<T...>) -> number,
	Destroy: (self: Signal<T...>) -> (),
}

type Node<T...> = {
	fn: (T...) -> (),
	next: Node<T...>?,
	prev: Node<T...>?,
	freeNext: Node<T...>?,
	connected: boolean,
	once: boolean,
	conn: _Connection<T...>,
	priority: number,
	owner: _Signal<T...>?,
}

type _Signal<T...> = Signal<T...> & {
	_head: Node<T...>?,
	_tail: Node<T...>?,
	_pool: Node<T...>?,
	_trash: Node<T...>?,
	_count: number,
	_destroyed: boolean,
	_mode: FireMode,
	_fire: (self: _Signal<T...>, T...) -> (),
	_firing: number,
	_prioCount: number,
}

type _Connection<T...> = Connection & {
	_node: Node<T...>?,
	_signal: _Signal<T...>?,
}

-- NOTE: used to clear handler refs on pooled nodes.
local def = function() end

-- FIXME: This debug path started as "temporary" and kinda stayed. Worth keeping?
local DEBUG = false

-- Cached runner coroutine for spawn/defer modes.
local freeRunnerThread: thread? = nil

local acquireRunnerThreadAndCallEventHandler: ((...any) -> (), ...any) -> ()
if DEBUG then
	acquireRunnerThreadAndCallEventHandler = function(fn, ...)
		local acquiredRunnerThread = freeRunnerThread
		freeRunnerThread = nil
		local packed = table.pack(pcall(fn, ...))
		local ok = packed[1]
		local err = packed[2]
		freeRunnerThread = acquiredRunnerThread
		if not ok then
			error(err, 0)
		end
	end
else
	acquireRunnerThreadAndCallEventHandler = function(fn, ...)
		local acquiredRunnerThread = freeRunnerThread
		freeRunnerThread = nil
		fn(...)
		freeRunnerThread = acquiredRunnerThread
	end
end

local function runEventHandlerInFreeThread()
	-- Resume with (fn, ...). Yield first so we don't keep "..." on the runner stack.
	while true do
		acquireRunnerThreadAndCallEventHandler(coroutine.yield())
	end
end

local function ensureFreeRunnerThread(): thread
	local t = freeRunnerThread
	if t then
		return t
	end
	local created = coroutine.create(runEventHandlerInFreeThread)
	if DEBUG then
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

local function assertAlive<T...>(signal: _Signal<T...>)
	if signal._destroyed then
		error("Signal is destroyed", 3)
	end
end

local function pushTrash<T...>(signal: _Signal<T...>, node: Node<T...>)
	-- During Fire we delay recycling so iteration never hits a reused node.
	node.fn = def :: any
	node.once = false
	node.conn = nil :: any
	node.priority = 0
	node.owner = nil
	local nxt = signal._trash
	node.freeNext = nxt
	signal._trash = node
end

local function recycleNode<T...>(signal: _Signal<T...>, node: Node<T...>)
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
	local raw = setmetatable({}, Connection) :: any
	raw.Connected = true
	raw._signal = signal
	raw._node = node
	return raw :: _Connection<T...>
end

local function disconnectNode<T...>(signal: _Signal<T...>, node: Node<T...>)
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
	local conn = self :: _Connection<any>
	if not conn.Connected then
		return
	end
	conn.Connected = false

	local node = conn._node
	local signal = conn._signal
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
	local s = asSignal(self)
	return connectInternal(s, fn, false, priority or 0)
end

function Signal:ConnectWithPriority<T...>(priority: number, fn: (T...) -> ()): Connection
	local s = asSignal(self)
	return connectInternal(s, fn, false, priority)
end

function Signal:Once<T...>(fn: (T...) -> (), priority: number?): Connection
	local s = asSignal(self)
	return connectInternal(s, fn, true, priority or 0)
end

function Signal:Wait<T...>(): T...
	local thread = coroutine.running()

	self:Once(function(...)
		task.spawn(thread, ...)
	end)

	return coroutine.yield()
end

function Signal:WaitTimeout<T...>(timeout: number): (boolean, T...)
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
	local s = asSignal(self)
	s._fire(s, ...)
end

function Signal:FireSync<T...>(...: T...)
	local s = asSignal(self)
	fireSync(s, ...)
end

function Signal:FireDeferred<T...>(...: T...)
	local s = asSignal(self)
	fireDefer(s, ...)
end

function Signal:FireSpawn<T...>(...: T...)
	local s = asSignal(self)
	fireSpawn(s, ...)
end

function Signal:DisconnectAll<T...>()
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
	local s = asSignal(self)
	return s._count
end

function Signal:Destroy<T...>()
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

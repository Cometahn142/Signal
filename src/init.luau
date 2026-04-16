--!strict

export type Connection = {
	Disconnect: (self: Connection) -> (),
	Connected: boolean,
}

export type Signal<T...> = {
	Connect: (self: Signal<T...>, fn: (T...) -> ()) -> Connection,
	Once: (self: Signal<T...>, fn: (T...) -> ()) -> Connection,
	Wait: (self: Signal<T...>) -> T...,
	Fire: (self: Signal<T...>, T...) -> (),
	DisconnectAll: (self: Signal<T...>) -> (),
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
	owner: _Signal<T...>?,
}

type _Signal<T...> = Signal<T...> & {
	_head: Node<T...>?,
	_tail: Node<T...>?,
	_pool: Node<T...>?,
	_trash: Node<T...>?,
	_destroyed: boolean,
	_firing: number,
}

type _Connection<T...> = Connection & {
	_node: Node<T...>?,
	_signal: _Signal<T...>?,
}

local def = function() end

local DEBUG = false -- Default 

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
	node.fn = def :: any
	node.once = false
	node.conn = nil :: any
	node.owner = nil
	local nxt = signal._trash
	node.freeNext = nxt
	signal._trash = node
end

local function recycleNode<T...>(signal: _Signal<T...>, node: Node<T...>)
	node.fn = def :: any
	node.once = false
	node.conn = nil :: any
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
	fresh.owner = nil
	return fresh :: Node<T...>
end

local function insertNode<T...>(signal: _Signal<T...>, node: Node<T...>)
	-- Always insert at head (O(1)).
	local head = signal._head
	if head then
		node.next = head
		head.prev = node
		signal._head = node
	else
		signal._head = node
		signal._tail = node
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

local function connectInternal<T...>(signal: _Signal<T...>, fn: (T...) -> (), once: boolean): Connection
	assertAlive(signal)
	local node = acquireNode(signal)
	node.fn = fn
	node.connected = true
	node.once = once
	node.prev = nil
	node.next = nil
	node.freeNext = nil
	node.owner = signal

	local conn = Connection.new(signal, node)
	node.conn = conn

	insertNode(signal, node)
	return conn
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

function Signal.new<T...>(): Signal<T...>
	local self = setmetatable({}, Signal) :: any
	local s = (self :: any) :: _Signal<T...>
	s._head = nil
	s._tail = nil
	s._pool = nil
	s._trash = nil
	s._destroyed = false
	s._firing = 0
	return self
end

function Signal:Connect<T...>(fn: (T...) -> ()): Connection
	local s = asSignal(self)
	return connectInternal(s, fn, false)
end

function Signal:Once<T...>(fn: (T...) -> ()): Connection
	local s = asSignal(self)
	return connectInternal(s, fn, true)
end

function Signal:Wait<T...>(): T...
	local thread = coroutine.running()

	self:Once(function(...)
		task.spawn(thread, ...)
	end)

	return coroutine.yield()
end

function Signal:Fire<T...>(...: T...)
	local s = asSignal(self)
	fireSpawn(s, ...)
end

function Signal:DisconnectAll<T...>()
	local s = asSignal(self)
	assertAlive(s)
	local cur = s._head
	s._head = nil
	s._tail = nil
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

function Signal:Destroy<T...>()
	local s = asSignal(self)
	if s._destroyed then
		return
	end
	self:DisconnectAll()
	s._destroyed = true
	s._pool = nil
	s._trash = nil
end

return Signal

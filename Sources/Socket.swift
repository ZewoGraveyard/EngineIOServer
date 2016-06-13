// Socket.swift
//
// The MIT License (MIT)
//
// Copyright (c) 2016 Zewo
//
// Permission is hereby granted, free of charge, to any person obtaining a copy
// of this software and associated documentation files (the "Software"), to deal
// in the Software without restriction, including without limitation the rights
// to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
// copies of the Software, and to permit persons to whom the Software is
// furnished to do so, subject to the following conditions:
//
// The above copyright notice and this permission notice shall be included in all
// copies or substantial portions of the Software.
//
// THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
// IMPLIED, INCLUDINbG BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
// FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
// AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
// LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
// OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
// SOFTWARE.

import HTTP
import Event
import Venice
import JSON

public class Socket {
	
	public enum State {
		case opening, open, closing, closed
	}
	
	public let id: String
	public let server: Server
	public let request: Request
	internal var upgrading = false
	internal var upgraded = false
	public var readyState: State = .opening
	internal var writeBuffer = [Packet]()
	internal var packetsFn = [Any]()
	internal var sentCallbackFn = [Any]()
	
	private var checkIntervalTimer: Timer?
	private var upgradeTimeoutTimer: Timer?
	private var pingTimeoutTimer: Timer?
	
	internal var _transport: TransportInternal
	
	public var transport: Transport {
		return _transport
	}
	
	internal let openEventEmitter = EventEmitter<Void>()
	internal let packetEventEmitter = EventEmitter<Packet>()
	internal let heartbeatEventEmitter = EventEmitter<Void>()
	internal let dataEventEmitter = EventEmitter<Data>()
	internal let errorEventEmitter = EventEmitter<String>()
	internal let closeEventEmitter = EventEmitter<(reason: TransportCloseReason, description: String?)>()
	internal let packetCreateEventEmitter = EventEmitter<Packet>()
	internal let flushEventEmitter = EventEmitter<[Packet]>()
	internal let drainEventEmitter = EventEmitter<Void>()
	internal let upgradeEventEmitter = EventEmitter<Transport>()
	
	private var onErrorEventListener: EventListener<String?>?
	private var onPacketEventListener: EventListener<Packet>?
	private var flushEventListener: EventListener<Void>?
	private var onCloseEventListener: EventListener<(reason: TransportCloseReason, description: String?)>?
	private var drainEventListener: EventListener<Void>?
	
	internal init(id: String, server: Server, request: Request, transport: TransportInternal) {
		self.id = id
		self.server = server
		self.request = request
		self._transport = transport
		
		setTransport(transport: transport)
		onOpen()
	}
	
	/// Called upon transport considered open
	private func onOpen() {
		readyState = .open
		
		_transport.sid = id
		
		// sends an `open` packet
		let data = JSONSerializer().serialize(json: .object([
			"sid": .string(id),
			"upgrades": getAvailableUpgrades(),
			"pingInterval": .number(.double(server.pingInterval * 1000)),
			"pingTimeout": .number(.double(server.pingTimeout * 1000))
		]))
		sendPacket(type: .open, data: data)
		
		openEventEmitter.safeEmit(event: ())
		setPingTimeout()
	}
	
	/// Called upon transport packet
	private func onPacket(packet: Packet) {
		guard readyState == .open else {
			return log("packet received with closed socket")
		}
		
		log("packet")
		packetEventEmitter.safeEmit(event: packet)
		
		// Reset ping timeout on any packet, incoming data is a good sign of other side's liveness
		setPingTimeout()
		
		switch (packet.type) {
		case .ping:
			log("got ping")
			sendPacket(type: .pong)
			heartbeatEventEmitter.safeEmit(event: ())
		case .error:
			onClose(reason: .parseError)
		case .message:
			dataEventEmitter.safeEmit(event: packet.data)
		default:
			break
		}
	}
	
	/// Called upon transport error
	private func onError(error: String?) {
		log("transport error: \(error)")
		onClose(reason: .transportError, description: error)
	}

	/// Sets and resets ping timeout timer based on client pings
	private func setPingTimeout() {
		self.pingTimeoutTimer?.stop()
		let pingTimeoutTimer = Timer(deadline: now() + server.pingInterval + server.pingTimeout)
		self.pingTimeoutTimer = pingTimeoutTimer
		co {
			pingTimeoutTimer.channel.receive()
			log("ping timeout")
			self.onClose(reason: .pingTimeout)
		}
	}
	
	/// Attaches handlers for the given transport
	private func setTransport(transport: TransportInternal) {
		log("setTransport")
		self._transport = transport
		onErrorEventListener = transport.errorEventEmitter.addListener(times: 1, listen: self.onError)
		onPacketEventListener = transport.packetEventEmitter.addListener(listen: self.onPacket)
		// TODO: Compiler crash
//		flushEventListener = transport.drainEventEmitter.addListener(listen: self.flush)
		flushEventListener = transport.drainEventEmitter.addListener { _ in self.flush() }
		onCloseEventListener = transport.closeEventEmitter.addListener(times: 1, listen: self.onClose)
		// this function will manage packet events (also message callbacks)
		setupSendCallback()
	}

	/// we force a polling cycle to ensure a fast upgrade
	private func upgradeCheck() {
		guard _transport.type == .polling && _transport.writable else {
			return
		}
		log("writing a noop packet to polling for fast upgrade")
		_transport.send(packets: [Packet(type: .noop)])
		
		let checkIntervalTimer = Timer(deadline: 0.1.fromNow())
		self.checkIntervalTimer = checkIntervalTimer
		co {
			checkIntervalTimer.channel.receive()
			self.upgradeCheck()
		}
	}
	
	// Upgrades socket to the given transport
	internal func maybeUpgrade(transport: TransportInternal) {
		log("might upgrade socket transport from \(self.transport.type) to \(transport.type)")
		
		upgrading = true
		
		var onPacketListener: EventListener<Packet>?
		var onTransportCloseListener: EventListener<(reason: TransportCloseReason, description: String?)>?
		var onErrorListener: EventListener<String?>?
		var onCloseListener: EventListener<(reason: TransportCloseReason, description: String?)>?
		
		let cleanup: () -> Void = {
			self.upgrading = false
			
			self.checkIntervalTimer?.stop()
			self.checkIntervalTimer = nil
			
			self.upgradeTimeoutTimer?.stop()
			self.upgradeTimeoutTimer = nil
			
			onPacketListener?.stop()
			onPacketListener = nil
			onTransportCloseListener?.stop()
			onTransportCloseListener = nil
			onErrorListener?.stop()
			onErrorListener = nil
			onCloseListener?.stop()
			onCloseListener = nil
		}
		
		// set transport upgrade timer
		
		let upgradeTimeoutTimer = Timer(deadline: server.upgradeTimeout.fromNow())
		self.upgradeTimeoutTimer = upgradeTimeoutTimer
		co {
			upgradeTimeoutTimer.channel.receive()
			log("client did not complete upgrade - closing transport")
			cleanup()
			if transport.state == TransportState.open {
				transport.close()
			}
		}
		
		onPacketListener = transport.packetEventEmitter.addListener { packet in
			log("maybeUpgrade -> onPacket -> \(packet)")
			if packet.type == .ping && (try? String(data: packet.data)) == "probe" {
				transport.send(packets: [Packet(type: .pong, data: "probe")])
				self.checkIntervalTimer?.stop()
				let checkIntervalTimer = Timer(deadline: 0.1.fromNow())
				self.checkIntervalTimer = checkIntervalTimer
				co {
					checkIntervalTimer.channel.receive()
					self.upgradeCheck()
				}
			} else if packet.type == .upgrade && self.readyState != .closed {
				log("got upgrade packet - upgrading")
				cleanup()
				self._transport.discard()
				self.upgraded = true
				self.clearTransport()
				self.setTransport(transport: transport)
				self.upgradeEventEmitter.safeEmit(event: transport)
				self.setPingTimeout()
				self.flush()
				if self.readyState == .closing {
					transport.close() {
						self.onClose(reason: .forcedClose)
					}
				}
			} else {
				cleanup()
				transport.close()
			}
		}
		
		let onError: ((String?) -> Void) = { error in
			log(level: .error, "client did not complete upgrade - \(error)")
			cleanup()
			transport.close()
		}
		
		onErrorListener = transport.errorEventEmitter.addListener(times: 1, listen: onError)
		
		onTransportCloseListener = transport.closeEventEmitter.addListener(times: 1) { _, _ in
			onError("transport closed")
		}
		
		onCloseListener = closeEventEmitter.addListener(times: 1) { _, _ in
			onError("socket closed")
		}
	}

	/// Clears listeners and timers associated with current transport
	private func clearTransport() {
		onErrorEventListener?.stop()
		onErrorEventListener = nil
		onPacketEventListener?.stop()
		onPacketEventListener = nil
		flushEventListener?.stop()
		flushEventListener = nil
		onCloseEventListener?.stop()
		onCloseEventListener = nil
		drainEventListener?.stop()
		drainEventListener = nil
		
		// silence further transport errors and prevent uncaught exceptions
		_transport.errorEventEmitter.addListener { error in
			log(level: .error, "error triggered by discarded transport: \(error)")
		}
		_transport.close()
		
		pingTimeoutTimer?.stop()
	}
	
	/// Called upon transport considered closed
	private func onClose(reason: TransportCloseReason, description: String? = nil) {
		guard readyState != .closed else { return }
		
		readyState = .closed
		
		pingTimeoutTimer?.stop()
		checkIntervalTimer?.stop()
		checkIntervalTimer = nil
		upgradeTimeoutTimer?.stop()
		
		packetsFn.removeAll()
		sentCallbackFn.removeAll()
		clearTransport()
		closeEventEmitter.safeEmit(event: (reason: reason, description: description))
		
		writeBuffer.removeAll()
	}

	/// Setup and manage send callback
	private func setupSendCallback() {
		drainEventListener = _transport.drainEventEmitter.addListener { _ in
			guard self.sentCallbackFn.count > 0 else { return }
			let seqFn = self.sentCallbackFn.removeFirst()
			if let seqFn = seqFn as? ((Transport) -> ()) {
				log("executing send callback")
				seqFn(self.transport)
			} else if let seqFnArr = seqFn as? [Any] {
				log("executing batch send callback")
				for obj in seqFnArr {
					guard let seqFn = obj as? ((Transport) -> ()) else { continue }
					seqFn(self.transport)
				}
			}
		}
	}
	
	/// Sends a message packet
	public func send(data: Data, options: PacketOptions = [], callback: ((Transport) -> Void)? = nil) {
		sendPacket(type: .message, data: data, options: options, callback: callback)
	}

	/// Sends a packet
	private func sendPacket(type: PacketType, data: Data = Data(), options: PacketOptions = [], callback: ((Transport) -> Void)? = nil) {
		guard self.readyState != .closing else { return }
		
		log("sending packet")
		
		let packet = Packet(type: type, data: data, options: options)
		
		// exports packetCreate event
		packetCreateEventEmitter.safeEmit(event: packet)
		
		writeBuffer.append(packet)
		
		//add send callback to object
		if let callback = callback {
			packetsFn.append(callback)
		}
		
		flush()
	}

	/// Attempts to flush the packets buffer
	private func flush(_: Any? = nil) {
		guard readyState != .closed && _transport.writable && !writeBuffer.isEmpty else { return }
		log("flushing buffer to transport")
		flushEventEmitter.safeEmit(event: writeBuffer)
		server.flushEventEmitter.safeEmit(event: (socket: self, writeBuffer: writeBuffer))
		let oldWriteBuffer = writeBuffer
		writeBuffer.removeAll()
		if transport.supportsFraming {
			sentCallbackFn += packetsFn
		} else {
			sentCallbackFn.append(packetsFn)
		}
		packetsFn.removeAll()
		_transport.send(packets: oldWriteBuffer)
		drainEventEmitter.safeEmit(event: ())
		server.drainEventEmitter.safeEmit(event: self)
	}
	
	/// Get available upgrades for this socket
	private func getAvailableUpgrades() -> JSON {
		var availableUpgrades = [JSON]()
//		var allUpgrades = this.server.upgrades(this.transport.name);
//		for (var i = 0, l = allUpgrades.length; i < l; ++i) {
//			var upg = allUpgrades[i];
//			if (this.server.transports.indexOf(upg) != -1) {
//				availableUpgrades.push(upg);
//			}
//		}
		availableUpgrades.append("websocket")
		return .array(availableUpgrades)
	}
	
	/// Closes the socket and underlying transport
	public func close(discard: Bool = true) {
		guard self.readyState == .open else { return }
		
		self.readyState = .closing
		
		if !self.writeBuffer.isEmpty {
			drainEventEmitter.addListener(times: 1) { _ in
				self.closeTransport(discard: discard)
			}
		} else {
			closeTransport(discard: discard)
		}
	}
	
	/// Closes the underlying transport
	private func closeTransport(discard: Bool) {
		if (discard) {
			_transport.discard()
		}
		
		_transport.close() {
			self.onClose(reason: .forcedClose)
		}
	}
	
	// MARK: - EventEmitter
	
	public func onMessage(listen: EventListener<Data>.Listen) -> EventListener<Data> {
		return dataEventEmitter.addListener(listen: listen)
	}
	
	public func onError(listen: EventListener<String>.Listen) -> EventListener<String> {
		return errorEventEmitter.addListener(listen: listen)
	}
	
	public func onClose(listen: EventListener<(reason: TransportCloseReason, description: String?)>.Listen) -> EventListener<(reason: TransportCloseReason, description: String?)> {
		return closeEventEmitter.addListener(listen: listen)
	}
	
}

// MARK: - Equatable

extension Socket: Equatable {}

public func ==(lhs: Socket, rhs: Socket) -> Bool {
	return lhs.id == rhs.id
}

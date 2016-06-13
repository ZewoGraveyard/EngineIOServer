// Transport.swift
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

public enum TransportType: String {
	case polling = "polling", websocket = "websocket"
}

public enum TransportState {
	case open, closing, closed
}

public enum TransportCloseReason: ErrorProtocol {
	case pingTimeout, clientError, parseError, transportError, serverClose, transportClose, forcedClose
}

public protocol Transport: class {
	var sid: String? { get }
	var state: TransportState { get }
	
	var type: TransportType { get }
	var supportsFraming: Bool { get }
	var handlesUpgrades: Bool { get }
	var upgradesTo: [TransportType] { get }
	var headers: Headers { get set }
}

protocol TransportInternal: Transport, Responder {
	var sid: String? { get set }
	var state: TransportState { get set }
	var discarded: Bool { get set }
	var writable: Bool { get set }
	var supportsBinary: Bool { get set }
	
	var packetEventEmitter: EventEmitter<Packet> { get }
	var drainEventEmitter: EventEmitter<Void> { get }
	var errorEventEmitter: EventEmitter<String?> { get }
	var closeEventEmitter: EventEmitter<(reason: TransportCloseReason, description: String?)> { get }
	
	func send(packets: [Packet])
	func doClose(callback: (() -> Void)?)
}

extension TransportInternal {
	/// Flags the transport as discarded
	func discard() {
		discarded = true
	}
	
	/// Closes the transport
	func close(callback: (() -> Void)? = nil) {
		guard state != .closed && state != .closing else { return }
		state = .closing
		doClose(callback: callback)
	}
}

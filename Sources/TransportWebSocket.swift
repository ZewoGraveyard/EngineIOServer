// TransportWebSocket.swift
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
import WebSocket

class TransportWebSocket: TransportInternal {
	
	var webSocket: WebSocket
	var sid: String?
	var state: TransportState = .open
	var discarded: Bool = false
	var writable: Bool = false
	var supportsBinary: Bool = false
	var type: TransportType = .websocket
	var supportsFraming: Bool = true
	var handlesUpgrades: Bool = true
	var upgradesTo: [TransportType] = []
	var headers: Headers = [:]
	
	var packetEventEmitter = EventEmitter<Packet>()
	var drainEventEmitter = EventEmitter<Void>()
	var errorEventEmitter = EventEmitter<String?>()
	var closeEventEmitter = EventEmitter<(reason: TransportCloseReason, description: String?)>()
	
	init(webSocket: WebSocket) {
		self.webSocket = webSocket
		
		log("webSocketDidOpen")
		
		webSocket.onBinary(self.onData)
		webSocket.onText { string in self.onData(data: string.data) }
		webSocket.onClose { _, _ in
			self.state = .closed
			self.closeEventEmitter.safeEmit(event: (reason: .transportClose, description: nil))
		}
		
		writable = true
	}
	
	/// Processes the incoming data
	func onData(data: Data) {
		log("received \(data)")
		
		if let packet = Parser.decodePacket(data: data) {
			packetEventEmitter.safeEmit(event: packet)
		} else {
			log(level: .error, "error decoding packet")
		}
	}
	
	/// Writes a packet payload
	func send(packets: [Packet]) {
		for packet in packets {
			let data = Parser.encodePacket(packet: packet)
			log("writing \(data)")
			
//			var options = []
//			if packet.options.contains(.Compress) {
//				options.insert(.Compress)
//			}
			
			writable = false
			
			do {
				try webSocket.send(data)
			} catch {
				errorEventEmitter.safeEmit(event: "write error")
				continue
			}
			
			writable = true
			drainEventEmitter.safeEmit(event: ())
		}
	}
	
	/// Closes the transport
	func doClose(callback: (() -> Void)?) {
		log("closing")
		do {
			try webSocket.close()
		} catch {
			log(level: .error, "close error: \(error)")
		}
		callback?()
	}
	
	/// ResponderType
	func respond(to request: Request) throws -> Response {
		return Response(status: .badRequest)
	}

}

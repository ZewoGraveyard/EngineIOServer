// TransportPolling.swift
//
// The MIT License (MIT)
//
// Copyright (c) 2015 Zewo
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
import Venice
import Event

class TransportPolling: TransportInternal {
	
	var sid: String?
	var state: TransportState = .open
	var discarded: Bool = false
	var writable: Bool = false
	var supportsBinary: Bool = false
	var type: TransportType = .polling
	var supportsFraming: Bool = false
	var handlesUpgrades: Bool = false
	var upgradesTo: [TransportType] = [.websocket]
	var headers: Headers = [:]
	
	var packetEventEmitter = EventEmitter<Packet>()
	var drainEventEmitter = EventEmitter<Void>()
	var errorEventEmitter = EventEmitter<String?>()
	var closeEventEmitter = EventEmitter<(reason: TransportCloseReason, description: String?)>()
	
	var shouldClose: (() -> Void)?
	
	var closeTimeout: Double = 30
	
	var request: Request?
	var dataRequest: Request?
	private let pollingChannel = Channel<Response>()
	
	/// ResponderType
	func respond(to request: Request) throws -> Response {
		switch request.method {
		case .get:
			return try onPollRequest(request: request)
		case .post:
			return try onDataRequest(request: request)
		default:
			return Response(status: .badRequest)
		}
	}
	
	/// The client sends a request awaiting for us to send data
	func onPollRequest(request: Request) throws -> Response {
		guard self.request == nil else {
			log("request overlap")
			errorEventEmitter.safeEmit(event: "overlap from client")
			return Response(status: .internalServerError)
		}
		
		log("setting request")
		self.request = request

//		request.onClose {
//			self.onError("poll connection closed prematurely")
//		}

		writable = true
		drainEventEmitter.safeEmit(event: ())
		
		// if we're still writable but had a pending close, trigger an empty send
		if writable && shouldClose != nil {
			log("triggering empty send to append close packet")
			send(packets: [Packet(type: .noop)])
		}
		
		log("BEFORE pollChannel")
		
		guard let response = pollingChannel.receive() else {
			return Response(status: .internalServerError)
		}
		
		log("AFTER pollChannel")
		
		return response
	}
	
	/// The client sends a request with data
	func onDataRequest(request: Request) throws -> Response {
		guard dataRequest == nil else {
			log("data request overlap from client")
			errorEventEmitter.safeEmit(event: "data request overlap from client")
			return Response(status: .internalServerError)
		}
		
		log("data request")
		
//		let isBinary = request.headers["content-type"] == "application/octet-stream"
		
		dataRequest = request
		
		defer {
			dataRequest = nil
		}
		
		let data = try dataRequest!.body.becomeBuffer()
		onData(data: data)
		
		let headers: Headers = [
			// text/html is required instead of text/plain to avoid an unwanted download dialog on certain user-agents
			"Content-Type": "text/html"
		]
		
		return Response(status: .ok, headers: self.headers(request: request, headers: headers), body: "ok")
	}
	
	/// Processes the incoming data payload
	func onData(data: Data) {
		log("received \(data)")
		for packet in Parser.decodePayload(data: data) {
			if packet.type == .close {
				log("got xhr close packet")
				onClose()
				return
			}
			packetEventEmitter.safeEmit(event: packet)
		}
	}
	
	/// Overrides onClose
	func onClose() {
		if writable {
			// close pending poll request
			send(packets: [Packet(type: .noop)])
		}
		state = .closed
		closeEventEmitter.safeEmit(event: (reason: .transportClose, description: nil))
	}
	
	/// Writes a packet payload
	func send(packets: [Packet]) {
		var packets = packets
		writable = false
		
		if let shouldClose = shouldClose {
			log("appending close packet to payload")
			packets.append(Packet(type: .close))
			shouldClose()
			self.shouldClose = nil
		}
		
		var options: PacketOptions = []
		for packet in packets {
			if packet.options.contains(.compress) {
				options.insert(.compress)
				break
			}
		}
		
		let data = Parser.encodePayload(packets: packets)
		write(data: data, options: options)
	}
	
	/// Writes data as response to poll request
	func write(data: Data, options: PacketOptions = []) {
		guard let request = self.request else {
			return log("no request")
		}
		
		log("writing \(data)")
		
		let isString: Bool
		if let _ = try? String(data: data) {
			isString = true
		} else {
			isString = false
		}
		
		let contentType: Header = isString ? "text/plain; charset=UTF-8" : "application/octet-stream"
		
		var headers: Headers = [
			"Content-Type": contentType
		]
		
		if request.isKeepAlive {
			headers["Connection"] = "keep-alive"
		}
		
		let respond: (Data) -> Void = { data in
			headers = self.headers(request: request, headers: headers)
			let response = Response(status: .ok, headers: headers, body: data)
			co {
				self.pollingChannel.send(response)
			}
			self.request = nil
		}
		
		respond(data)
		
//		if (!this.httpCompression || !options.compress) {
//			respond(data);
//			return;
//		}
//
//		var len = isString ? Buffer.byteLength(data) : data.length;
//		if (len < this.httpCompression.threshold) {
//			respond(data);
//			return;
//		}
//
//		var encoding = accepts(this.req).encodings(['gzip', 'deflate']);
//		if (!encoding) {
//			respond(data);
//			return;
//		}
//
//		this.compress(data, encoding, function(err, data) {
//			if (err) {
//				self.res.writeHead(500);
//				self.res.end();
//				callback(err);
//				return;
//			}
//		
//			headers['Content-Encoding'] = encoding;
//			respond(data);
//		});
	}
	
//	/// Compresses data
//	private func compress(data: Data, encoding: String, callback: (() -> Void)) {
//		EngineIOLog("compressing")
//		
//		var buffers = [];
//		var nread = 0;
//		
//		compressionMethods[encoding](this.httpCompression)
//		.on('error', callback)
//		.on('data', function(chunk) {
//			buffers.push(chunk);
//			nread += chunk.length;
//		})
//		.on('end', function() {
//			callback(null, Buffer.concat(buffers, nread));
//		})
//		.end(data);
//	}
	
	/// Closes the transport
	func doClose(callback: (() -> Void)?) {
		log("closing")
		
		if let _ = self.dataRequest {
			log("aborting ongoing data request")
			co {
				self.pollingChannel.send(Response(status: .internalServerError))
			}
		}
		
		var timer: Timer?
		
		let closeCallback = {
			timer?.stop()
			callback?()
			self.onClose()
		}
		
		if writable {
			log("transport writable - closing right away")
			send(packets: [Packet(type: .close, options: [.compress])])
			closeCallback()
		} else if discarded {
			log("transport discarded - closing right away")
			closeCallback()
		} else {
			log("transport not writable - buffering orderly close")
			self.shouldClose = closeCallback
			let _timer = Timer(deadline: closeTimeout.fromNow())
			timer = _timer
			co {
				_timer.channel.receive()
				closeCallback()
			}
		}
	}
	
	/// Returns headers for a response
	func headers(request: Request, headers: Headers) -> Headers {
		var headers = headers
		
		// prevent XSS warnings on IE (https://github.com/LearnBoost/socket.io/pull/1333)
		if let ua = request.headers["user-agent"].first where ua.contains(";MSIE") || ua.contains("Trident/") {
			headers["X-XSS-Protection"] = "0"
		}
		
		for (header, value) in self.headers {
			headers[header] = value
		}
		
		return headers
	}
	
}

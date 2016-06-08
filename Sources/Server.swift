// Server.swift
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

import POSIX
import Event
import Venice
import JSON
import WebSocketServer

internal extension EventEmitter {
	func safeEmit(event: T) {
		do {
			try emit(event)
		} catch {
			log(level: .error, "error: \(error)")
		}
	}
}

public enum ServerError: Int, ErrorProtocol, CustomStringConvertible {
	case unknownTransport = 0, unknownSid, badHandshakeMethod, badRequest
	
	public var description: String {
		switch self {
		case .unknownTransport:
			return "Transport unknown"
		case .unknownSid:
			return "Session ID unknown"
		case .badHandshakeMethod:
			return "Bad handshake method"
		case .badRequest:
			return "Bad request"
		}
	}
}

public struct LogLevel: OptionSet {
    public let rawValue: Int32

    public init(rawValue: Int32) {
        self.rawValue = rawValue
    }

    public static let trace   = LogLevel(rawValue: 1 << 0)
    public static let debug   = LogLevel(rawValue: 1 << 1)
    public static let info    = LogLevel(rawValue: 1 << 2)
    public static let warning = LogLevel(rawValue: 1 << 3)
    public static let error   = LogLevel(rawValue: 1 << 4)
    public static let fatal   = LogLevel(rawValue: 1 << 5)
    public static let all     = LogLevel(rawValue: ~0)
}

internal func log(level: LogLevel = .debug, _ item: Any) {
	guard level.rawValue >= Server.logLevel.rawValue else { return }
//	log.log(level, item: item)
	print(item)
}

public class Server: Responder, Middleware {
	
	public static var logLevel: LogLevel = .error
	
	private var webSocketServer: WebSocketServer.Server!
	
	public var pingTimeout: Double = 60
	public var pingInterval: Double = 25
	public var upgradeTimeout: Double = 10
	public var transports: [TransportType] = [.polling, .websocket]
	public var allowUpgrades = true
	public var cookie: String? = "io"
	public var path = "/engine.io"
	
	public private(set) var clients = [String: Socket]()
	
	let connectionEventEmitter = EventEmitter<Socket>()
	let drainEventEmitter = EventEmitter<Socket>()
	let flushEventEmitter = EventEmitter<(socket: Socket, writeBuffer: [Packet])>()
	
	// MARK: - Init
	
	public init() {
		self.webSocketServer = WebSocketServer.Server(onWebSocket)
	}
	
	public convenience init(onConnect: EventListener<Socket>.Listen) {
		self.init()
		self.onConnect(listen: onConnect)
	}
	
	/// Returns a list of available transports for upgrade given a certain transport
	private func upgrades(transport: Transport) -> [TransportType] {
		guard allowUpgrades else { return [] }
		return transport.upgradesTo
	}
	
	/// Verifies a request
	private func verify(request: Request) -> ServerError? {
		// transport check
		guard let _transportStr = request.uri.query["transport"].first, transportStr = _transportStr, transport = TransportType(rawValue: transportStr) where transports.contains(transport) else {
			return .unknownTransport
		}
		
		// sid check
		request.uri.query
		if let _sid = request.uri.query["sid"].first, sid = _sid {
			guard let client = clients[sid] else {
				return .unknownSid
			}
			if !request.isWebSocket && client.transport.type != transport {
				log("bad request: unexpected transport without upgrade")
				return .badRequest
			}
		} else if request.method != .get {
			return .badHandshakeMethod
		}
		
		return nil
	}
	
	/// Closes all clients
	public func close() {
		log("closing all open clients")
		for (_, socket) in clients {
			socket.close(discard: true)
		}
	}
	
	/// Sends an Engine.IO Error Message
	private func sendErrorMessage(request: Request, error: ServerError) -> Response {
		var headers: Headers = [
			"Content-Type": "application/json"
		]
		
		if let origin = request.headers["origin"].first {
			headers["Access-Control-Allow-Credentials"] = "true"
			headers["Access-Control-Allow-Origin"] = Header(origin)
		} else {
			headers["Access-Control-Allow-Origin"] = "*"
		}
		
		let data = JSONSerializer().serialize(json: .objectValue([
			"code": .numberValue(Double(error.rawValue)),
			"message": .stringValue(error.description)
		]))
		
		return Response(status: .badRequest, headers: headers, body: data)
	}
	
	/// generate a socket id
	private func generateId() throws -> String {
		var data = Data()
		for _ in 0..<15 { data.append(Byte(Double(UInt8.max)*(Double(rand()) / 2147483647))) } // RAND_MAX
		return Base64.urlSafeEncode(data)
	}
	
	/// Handshakes a new client
	private func handshake(request: Request, webSocket: WebSocket? = nil) throws -> Response {
		guard let transport = transportForRequest(request: request, webSocket: webSocket) else {
			return sendErrorMessage(request: request, error: .badRequest)
		}
		
		if request.uri.query["b64"].first != nil {
			transport.supportsBinary = false
		} else {
			transport.supportsBinary = true
		}
		
		let sid = try generateId()
		
		log("handshaking client: \(sid)")
		
		let socket = Socket(id: sid, server: self, request: request, transport: transport)
		
		if let cookie = self.cookie {
			transport.headers["Set-Cookie"] = Header("\(cookie)=\(sid)")
		}
		
		clients[sid] = socket
		
		socket.closeEventEmitter.addListener(times: 1) { _, _ in
			self.clients.removeValue(forKey: sid)
		}
		
		connectionEventEmitter.safeEmit(event: socket)
		
		return try transport.respond(to: request)
	}
	
	/// Called upon a webSocket connection
//	request: Request, 
	private func onWebSocket(webSocket: WebSocket, request: Request) throws {
		log("handleUpgrade socket: \(webSocket)")
		
		if let _sid = request.uri.query["sid"].first, sid = _sid {
			
			guard let client = clients[sid] where !client.upgrading && !client.upgraded else {
				log("upgrade attempt for closed client || transport has already been trying to upgrade || transport had already been upgraded")
				return try webSocket.close()
			}
			
			guard let transport = transportForRequest(request: request, webSocket: webSocket) where transport.handlesUpgrades else {
				log("no transport for websockets")
				return try webSocket.close()
			}
			
			log("upgrading existing transport")
			
			if request.uri.query["b64"].first != nil {
				transport.supportsBinary = false
			} else {
				transport.supportsBinary = true
			}
			
			client.maybeUpgrade(transport: transport)
			
		} else {
			try handshake(request: request, webSocket: webSocket)
		}
	}
	
	private func transportForRequest(request: Request, webSocket: WebSocket? = nil) -> TransportInternal? {
		guard let _transportStr = request.uri.query["transport"].first, transportStr = _transportStr, transportType = TransportType(rawValue: transportStr) else {
			return nil
		}
		
		var transport: TransportInternal?
		
		switch transportType {
		case .polling:
			if let _j = request.uri.query["j"].first, j = _j {
				transport = TransportPollingJSONP(j: j)
			} else {
				transport = TransportPollingXHR()
			}
		case .websocket:
			if let webSocket = webSocket {
				transport = TransportWebSocket(webSocket: webSocket)
			}
		}
		
		return transport
	}
	
	// MARK: - MiddlewareType
	
	public func respond(to request: Request, chainingTo next: Responder) throws -> Response {
		guard let path = request.uri.path where path.starts(with: self.path) else {
			return try next.respond(to: request)
		}
		
		log("handling \(request.method) http request \(request.uri)")
		
		if let error = verify(request: request) {
			return sendErrorMessage(request: request, error: error)
		}
		
		if request.isWebSocket {
			return try webSocketServer.respond(to: request)
		} else {
			if let _sid = request.uri.query["sid"].first, sid = _sid, client = clients[sid] {
				return try client._transport.respond(to: request)
			} else {
				return try handshake(request: request)
			}
		}
	}
	
	// MARK: - ResponderType
	
	/// Handles an Engine.IO HTTP request
	public func respond(to request: Request) throws -> Response {
		if let path = request.uri.path where path.starts(with: self.path) {
			return try respond(to: request, chainingTo: self)
		} else {
			return Response(status: .badRequest)
		}
	}
	
	// MARK: - EventEmitter
	
	public func onConnect(listen: EventListener<Socket>.Listen) -> EventListener<Socket> {
		return connectionEventEmitter.addListener(listen: listen)
	}
	
}

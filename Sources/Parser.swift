// Parser.swift
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

import C7
import Base64

class Parser {
	
	/// Encodes a packet == <packet type id> [ <data> ] == Example: 5hello world|3|4
	/// Binary is encoded in an identical principle
	static func encodePacket(packet: Packet) -> String {
//		if (Buffer.isBuffer(packet.data)) {
//			return encodeBuffer(packet, supportsBinary, callback);
//		} else if (packet.data && (packet.data.buffer || packet.data) instanceof ArrayBuffer) {
//			return encodeArrayBuffer(packet, supportsBinary, callback);
//		}
		
		// Sending data as a utf-8 string
		var encoded = String(packet.type.rawValue)
		
		if let string = try? String(data: packet.data) {
			encoded += string
		}
		
		return encoded
	}
	
	/**
	* Encode Buffer data
	*/
	static func encodeBuffer(packet: Packet, supportsBinary: Bool, callback: Any? = nil) {
		//		var data = packet.data;
		//		if (!supportsBinary) {
		//		return exports.encodeBase64Packet(packet, callback);
		//		}
		//
		//		var typeBuffer = new Buffer(1);
		//		typeBuffer[0] = packets[packet.type];
		//		return callback(Buffer.concat([typeBuffer, data]));
	}
	
	static func encodeArrayBuffer(packet: Packet, supportsBinary: Bool, callback: Any? = nil) {
		//		var data = packet.data.buffer || packet.data;
		//
		//		if (!supportsBinary) {
		//		return exports.encodeBase64Packet(packet, callback);
		//		}
		//
		//		var contentArray = new Uint8Array(data);
		//		var resultBuffer = new Buffer(1 + data.byteLength);
		//
		//		resultBuffer[0] = packets[packet.type];
		//		for (var i = 0; i < contentArray.length; i++){
		//		resultBuffer[i+1] = contentArray[i];
		//		}
		//		return callback(resultBuffer);
	}
	
	/// Encodes a packet with binary data in a base64 string
	static func encodeBase64Packet(packet: Packet, callback: Any? = nil) {
		//		if (!Buffer.isBuffer(packet.data)) {
		//		var buf = new Buffer(packet.data.byteLength);
		//		for (var i = 0; i < buf.length; i++) {
		//		buf[i] = packet.data[i];
		//		}
		//		packet.data = buf;
		//		}
		//
		//		var message = 'b' + packets[packet.type];
		//		message += packet.data.toString('base64');
		//		return callback(message);
	}
	
	/// Decodes a packet
	static func decodePacket(data: Data) -> Packet? {
		guard let str = try? String(data: data) else { return nil }
		
		if str.characters.first == "b" {
			let base64str = String(str.characters.dropFirst())
			return decodeBase64Packet(msg: base64str)
		}
		
		guard let char = str.characters.first, let number = Int(String(char)), let type = PacketType(rawValue: number) else {
			return nil
		}
		
		return Packet(type: type, data: String(str.characters.dropFirst()).data)
	}
	
	// Decodes a packet encoded in a base64 string.
	static func decodeBase64Packet(msg: String) -> Packet? {
		guard let char = msg.characters.first, let number = Int(String(char)), let type = PacketType(rawValue: number) else {
			return nil
		}
		
		let substr = String(msg.characters.dropFirst())
		let decoded = Base64.decode(substr)
		
		return Packet(type: type, data: decoded)
	}
	
	/// Encodes multiple messages (payload) == <length>:data == Example: 11:hello world2:hi
	/// If any contents are binary, they will be encoded as base64 strings. Base64 encoded strings are marked with a b before the length specifier
	static func encodePayload(packets: [Packet], supportsBinary: Bool = false) -> Data {
//		if (supportsBinary) {
//			return exports.encodePayloadAsBinary(packets, callback);
//		}
		guard !packets.isEmpty else { return "0:" }
		var encoded = ""
		for packet in packets {
			let packetStr = self.encodePacket(packet: packet)
			encoded += "\(packetStr.characters.count):"+packetStr
		}
		return encoded.data
	}
	
	// Decodes data when a payload is maybe expected. Possible binary contents are decoded from their base64 representation
	static func decodePayload(data: Data) -> [Packet] {
		guard let str = try? String(data: data) else {
//			return exports.decodePayloadAsBinary(data, binaryType, callback);
			return []
		}
		guard !str.isEmpty else { log("msg isEmpty"); return [] }
		var packets = [Packet]()
		var lengthStr = ""
		
		var skipCharacters = 0
		for (i, char) in str.characters.enumerated() {
			if skipCharacters > 0 {
				skipCharacters -= 1
				continue
			}
			
			if char == ":" {
				guard !lengthStr.isEmpty else { log("lengthStr isEmpty"); return [] }
				guard let n = Int(lengthStr) else { log("lengthStr not int"); return [] }
				let substr = Array(str.characters)[i+1 ..< i+1+n]
				guard substr.count == n else { log("no substr"); return [] }
				if n > 0 {
					guard let packet = decodePacket(data: String(String.CharacterView(substr)).data) else { return [] }
					packets.append(packet)
				}
				skipCharacters += n
				lengthStr = ""
			} else {
				lengthStr += String(char)
			}
		}
		guard lengthStr.isEmpty else { return [] }
		return packets
	}
	
	//	/**
	// *
	// * Converts a buffer to a utf8.js encoded string
	// *
	// * @api private
	// */
	//
	//	function bufferToString(buffer) {
	//	var str = '';
	//	for (var i = 0; i < buffer.length; i++) {
	//	str += String.fromCharCode(buffer[i]);
	//	}
	//	return str;
	//	}
	//
	//	/**
	// *
	// * Converts a utf8.js encoded string to a buffer
	// *
	// * @api private
	// */
	//
	//	function stringToBuffer(string) {
	//	var buf = new Buffer(string.length);
	//	for (var i = 0; i < string.length; i++) {
	//	buf.writeUInt8(string.charCodeAt(i), i);
	//	}
	//	return buf;
	//	}
	//
	//	/**
	// * Encodes multiple messages (payload) as binary.
	// *
	// * <1 = binary, 0 = string><number from 0-9><number from 0-9>[...]<number
	// * 255><data>
	// *
	// * Example:
	// * 1 3 255 1 2 3, if the binary contents are interpreted as 8 bit integers
	// *
	// * @param {Array} packets
	// * @return {Buffer} encoded payload
	// * @api private
	// */
	//
	//	exports.encodePayloadAsBinary = function (packets, callback) {
	//	if (!packets.length) {
	//	return callback(new Buffer(0));
	//	}
	//
	//	function encodeOne(p, doneCallback) {
	//	exports.encodePacket(p, true, true, function(packet) {
	//
	//	if (typeof packet === 'string') {
	//	var encodingLength = '' + packet.length;
	//	var sizeBuffer = new Buffer(encodingLength.length + 2);
	//	sizeBuffer[0] = 0; // is a string (not true binary = 0)
	//	for (var i = 0; i < encodingLength.length; i++) {
	//	sizeBuffer[i + 1] = parseInt(encodingLength[i], 10);
	//	}
	//	sizeBuffer[sizeBuffer.length - 1] = 255;
	//	return doneCallback(null, Buffer.concat([sizeBuffer, stringToBuffer(packet)]));
	//	}
	//
	//	var encodingLength = '' + packet.length;
	//	var sizeBuffer = new Buffer(encodingLength.length + 2);
	//	sizeBuffer[0] = 1; // is binary (true binary = 1)
	//	for (var i = 0; i < encodingLength.length; i++) {
	//	sizeBuffer[i + 1] = parseInt(encodingLength[i], 10);
	//	}
	//	sizeBuffer[sizeBuffer.length - 1] = 255;
	//	doneCallback(null, Buffer.concat([sizeBuffer, packet]));
	//	});
	//	}
	//
	//	map(packets, encodeOne, function(err, results) {
	//	return callback(Buffer.concat(results));
	//	});
	//	};
	//
	//	/*
	// * Decodes data when a payload is maybe expected. Strings are decoded by
	// * interpreting each byte as a key code for entries marked to start with 0. See
	// * description of encodePayloadAsBinary
	// * @param {Buffer} data, callback method
	// * @api public
	// */
	//
	//	exports.decodePayloadAsBinary = function (data, binaryType, callback) {
	//	if (typeof binaryType === 'function') {
	//	callback = binaryType;
	//	binaryType = null;
	//	}
	//
	//	var bufferTail = data;
	//	var buffers = [];
	//
	//	while (bufferTail.length > 0) {
	//	var strLen = '';
	//	var isString = bufferTail[0] === 0;
	//	var numberTooLong = false;
	//	for (var i = 1; ; i++) {
	//	if (bufferTail[i] == 255)  break;
	//	// 310 = char length of Number.MAX_VALUE
	//	if (strLen.length > 310) {
	//	numberTooLong = true;
	//	break;
	//	}
	//	strLen += '' + bufferTail[i];
	//	}
	//	if(numberTooLong) return callback(err, 0, 1);
	//	bufferTail = bufferTail.slice(strLen.length + 1);
	//
	//	var msgLength = parseInt(strLen, 10);
	//
	//	var msg = bufferTail.slice(1, msgLength + 1);
	//	if (isString) msg = bufferToString(msg);
	//	buffers.push(msg);
	//	bufferTail = bufferTail.slice(msgLength + 1);
	//	}
	//	
	//	var total = buffers.length;
	//	buffers.forEach(function(buffer, i) {
	//	callback(exports.decodePacket(buffer, binaryType, true), i, total);
	//	});
	//	};
	
}

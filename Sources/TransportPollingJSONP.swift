// TransportPollingJSONP.swift
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

import POSIXRegex
import String
import JSON

class TransportPollingJSONP: TransportPolling {
	
	private let rSlashesRegex: Regex
	private let rDoubleSlashesRegex: Regex
	private let u2028Regex: Regex
	private let u2029Regex: Regex
	
	private let j: String
	
	init?(j: String) {
		do {
			self.rSlashesRegex = try Regex(pattern: "\\\\\\\\n")
			self.rDoubleSlashesRegex = try Regex(pattern: "\\\\\\\\\n")
			self.u2028Regex = try Regex(pattern: "\u{2028}")
			self.u2029Regex = try Regex(pattern: "\u{2029}")
		} catch {
			return nil
		}
		
		let characterSet = CharacterSet.digits.inverted
		self.j = String(j.characters.filter({ !characterSet.contains(character: $0) }))
		super.init()
	}
	
	/// Handles incoming data
	/// Due to a bug in \n handling by browsers, we expect a escaped string
	override func onData(data: Data) {
		guard let string = try? String(data: data) else {
			return super.onData(data: data)
		}
		// client will send already escaped newlines as \\\\n and newlines as \\n
		// \\n must be replaced with \n and \\\\n with \\n

		var replaced = rSlashesRegex.replace(string, withTemplate: "\n")
		replaced = rDoubleSlashesRegex.replace(replaced, withTemplate: "\\\\n")
		super.onData(data: replaced.data)
	}

	/// Writes data as response to poll request
	override func write(data: Data, options: PacketOptions) {
		// we must output valid javascript, not valid json
		// see: http://timelessrepo.com/json-isnt-a-javascript-subset
		guard let string = try? String(data: data) else {
			return super.write(data: data)
		}
		var js = JSONSerializer().serializeToString(json: .string(string))
		js = u2028Regex.replace(js, withTemplate: "\\u2028")
		js = u2029Regex.replace(js, withTemplate: "\\u2029")
		super.write(data: ("___eio[" + j + "](" + js + ");").data, options: options)
	}
	
}

// TransportPollingXHR.swift
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

class TransportPollingXHR: TransportPolling {
	
	override func respond(to request: Request) throws -> Response {
		if request.method == .options {
			var headers = self.headers(request: request)
			headers["Access-Control-Allow-Headers"] = "Content-Type"
			return Response(status: .ok, headers: headers)
		} else {
			return try super.respond(to: request)
		}
	}
	
	override func headers(request: Request, headers: Headers = [:]) -> Headers {
		var headers = headers
		
		if let origin = request.headers["origin"].first {
			headers["Access-Control-Allow-Credentials"] = "true"
			headers["Access-Control-Allow-Origin"] = Header(origin)
		} else {
			headers["Access-Control-Allow-Origin"] = "*"
		}
		
		return super.headers(request: request, headers: headers)
	}
	
}

import PackageDescription

let package = Package(
    name: "EngineioServer",
    dependencies: [
		.Package(url: "https://github.com/Zewo/WebSocketServer.git", majorVersion: 0, minor: 1),
		.Package(url: "https://github.com/VeniceX/Venice.git", majorVersion: 0, minor: 7),
		.Package(url: "https://github.com/Zewo/JSON.git", majorVersion: 0, minor: 7),
		.Package(url: "https://github.com/Zewo/String.git", majorVersion: 0, minor: 7),
    ]
)

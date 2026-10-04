import Foundation
import Network

/// Private loopback transport for a single host-provided space capability.
/// This is not the MCP transport: the stdio adapter owns MCP negotiation.
@MainActor
public final class LocalRuntimeBridge {
  public typealias Handler = @MainActor (String, JSONValue) async throws -> JSONValue
  private let handler: Handler
  private let allowsWrites: Bool
  private let token = UUID().uuidString + UUID().uuidString
  private var listener: NWListener?
  private var startup: CheckedContinuation<JSONValue, Error>?
  private var authority = ""
  private var connections: [UUID: NWConnection] = [:]
  private var jobs: [UUID: Task<Void, Never>] = [:]

  public init(allowsWrites: Bool = false, handler: @escaping Handler) {
    self.allowsWrites = allowsWrites
    self.handler = handler
  }

  public func start() async throws -> JSONValue {
    guard listener == nil else { throw HarnessError.message("Runtime bridge is already running.") }
    let parameters = NWParameters.tcp
    parameters.requiredLocalEndpoint = .hostPort(host: "127.0.0.1", port: .any)
    let server = try NWListener(using: parameters)
    listener = server
    server.newConnectionHandler = { [weak self] connection in
      Task { @MainActor in self?.accept(connection) }
    }
    server.stateUpdateHandler = { [weak self, weak server] state in
      Task { @MainActor in
        guard let self else { return }
        switch state {
        case .ready:
          guard let port = server?.port, let startup = self.startup else { return }
          self.authority = "127.0.0.1:\(port.rawValue)"
          self.startup = nil
          startup.resume(
            returning: .object([
              "version": .number(1), "url": .string("http://" + self.authority),
              "token": .string(self.token),
            ]))
        case .failed(let error): self.stop(error: error)
        default: break
        }
      }
    }
    return try await withCheckedThrowingContinuation {
      startup = $0
      server.start(queue: .main)
    }
  }

  public func stop() { stop(error: CancellationError()) }

  private func stop(error: Error) {
    startup?.resume(throwing: error)
    startup = nil
    listener?.cancel()
    listener = nil
    for job in jobs.values { job.cancel() }
    jobs.removeAll()
    for connection in connections.values { connection.cancel() }
    connections.removeAll()
  }

  private func accept(_ connection: NWConnection) {
    guard listener != nil, connections.count < 8 else {
      connection.cancel()
      return
    }
    let id = UUID()
    connections[id] = connection
    connection.start(queue: .main)
    read(connection, id: id, buffer: Data())
    Task { [weak self] in
      try? await Task.sleep(for: .seconds(70))
      self?.close(id)
    }
  }

  private func close(_ id: UUID) {
    jobs.removeValue(forKey: id)?.cancel()
    connections.removeValue(forKey: id)?.cancel()
  }

  private func read(_ connection: NWConnection, id: UUID, buffer: Data) {
    connection.receive(minimumIncompleteLength: 1, maximumLength: 65536) {
      [weak self] bytes, _, complete, error in
      Task { @MainActor in
        guard let self, self.connections[id] != nil else {
          connection.cancel()
          return
        }
        var accumulated = buffer
        if let bytes { accumulated.append(bytes) }
        do {
          if let request = try CallbackRequest.parse(accumulated) {
            self.respond(request, connection: connection, id: id)
          } else if complete || error != nil {
            self.close(id)
          } else {
            self.read(connection, id: id, buffer: accumulated)
          }
        } catch {
          self.send(
            .object(["error": .string("Invalid request.")]), status: "400 Bad Request",
            connection: connection, id: id)
        }
      }
    }
  }

  private func respond(_ request: CallbackRequest, connection: NWConnection, id: UUID) {
    guard request.method == "POST", request.headers["host"] == authority,
      request.headers["origin"] == nil, request.headers["sec-fetch-site"] == nil,
      request.headers["authorization"] == "Bearer " + token,
      request.headers["content-type"] == "application/json"
    else {
      send(
        .object(["error": .string("Unauthorized runtime connection.")]), status: "403 Forbidden",
        connection: connection, id: id)
      return
    }
    if request.path == "/tools" {
      send(
        .object([
          "tools": .array(
            SpaceBuildTools.definitions + (allowsWrites ? [SpaceBuildTools.applyDefinition] : []))
        ]), connection: connection, id: id)
      return
    }
    guard request.path == "/call",
      let value = try? JSONDecoder().decode(JSONValue.self, from: request.body),
      case .object(let fields) = value, Set(fields.keys) == ["name", "arguments"],
      let name = value["name"].string
    else {
      send(
        .object(["error": .string("Invalid runtime operation.")]), status: "400 Bad Request",
        connection: connection, id: id)
      return
    }
    jobs[id] = Task { [weak self] in
      guard let self else { return }
      let result: JSONValue
      do {
        if name == "tonk_apply" && !allowsWrites {
          throw HarnessError.message("This runtime connection is read-only.")
        }
        _ = try SpaceBuildTools.document(tool: name, arguments: value["arguments"])
        result = .object(["result": try await handler(name, value["arguments"])])
      } catch {
        let detail =
          (error as NSError).userInfo["WKJavaScriptExceptionMessage"] as? String
          ?? error.localizedDescription
        result = .object(["error": .string(String(detail.prefix(2000)))])
      }
      guard !Task.isCancelled, connections[id] != nil else { return }
      send(result, connection: connection, id: id)
    }
  }

  private func send(
    _ value: JSONValue, status: String = "200 OK", connection: NWConnection, id: UUID
  ) {
    guard let body = try? JSONEncoder().encode(value) else {
      close(id)
      return
    }
    var response = Data(
      "HTTP/1.1 \(status)\r\nContent-Type: application/json\r\nContent-Length: \(body.count)\r\nCache-Control: no-store\r\nConnection: close\r\n\r\n"
        .utf8)
    response.append(body)
    connection.send(
      content: response,
      completion: .contentProcessed { [weak self] _ in
        Task { @MainActor in self?.close(id) }
      })
  }
}

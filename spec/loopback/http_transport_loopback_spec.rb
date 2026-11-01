require "rails_helper"
require "socket"

# Real sockets against a server on 127.0.0.1 (design D10). Excluded from the
# default run; execute with:
#
#   bundle exec rspec --tag loopback spec/loopback
#
# What it observes: read timeouts (before the headers and in the middle of the
# body) and a refused connection, with both adapters, using HTTP.rb's real
# llhttp parser. What it does not demonstrate: connection timeouts, the TLS
# handshake (timeout or errors) and DNS.
RSpec.describe "HTTP transports against a local server", loopback: true do
  # Last-resort guard: aborts the example; cleanup runs in `ensure` and is bounded.
  around do |example|
    ::Timeout.timeout(5) { example.run }
  end

  def monotonic_now
    Process.clock_gettime(Process::CLOCK_MONOTONIC)
  end

  def read_request_head(client)
    head = +""
    head << client.readpartial(4096) until head.include?("\r\n\r\n")
    head
  end

  # Starts a server in this thread (so it already listens), serves each
  # connection in a helper thread with `handler`, and waits for an explicit
  # readiness signal before yielding.
  def with_server(handler)
    server = TCPServer.new("127.0.0.1", 0)
    events = Thread::Queue.new
    accepted = Thread::Queue.new
    thread = Thread.new do
      Thread.current.report_on_exception = false
      events << :ready
      loop do
        client = server.accept
        accepted << client
        handler.call(client, events)
      end
    rescue IOError, SystemCallError
      # The server was closed by the cleanup.
    end
    resources = { server: server, thread: thread, accepted: accepted, events: events, port: server.addr[1] }
    raise "the local server did not signal readiness" unless events.pop(timeout: 1) == :ready

    WebMock.disable_net_connect!(allow: "127.0.0.1:#{resources[:port]}")
    yield resources
  ensure
    WebMock.disable_net_connect!
    cleanup(resources) if resources
  end

  # Bounded: closing does not wait, and the thread gets one second to finish.
  def cleanup(resources)
    resources[:sockets] = []
    resources[:sockets] << resources[:accepted].pop until resources[:accepted].empty?
    resources[:sockets].each { |socket| socket.close unless socket.closed? }
    resources[:server].close unless resources[:server].closed?
    resources[:thread].kill
    resources[:joined] = resources[:thread].join(1)
  end

  def expect_cleaned_up(resources)
    expect(resources[:joined]).not_to be_nil, "the server thread was still alive after join(1)"
    expect(resources[:thread]).not_to be_alive
    expect(resources[:server]).to be_closed
    expect(resources[:sockets]).to all(be_closed)
    # Extra evidence, filtered by this port and this process: nothing listens,
    # and no client socket of this process stays open towards the server.
    expect(`ss -Hltnp "sport = :#{resources[:port]}"`).not_to include("pid=#{Process.pid},")
    expect(`ss -Htnp "dport = :#{resources[:port]}"`).not_to include("pid=#{Process.pid},")
  end

  def report(label, elapsed, port)
    warn format("[loopback] %-55s %.3f s (port %d)", label, elapsed, port)
  end

  # Server handlers: read the request, signal it and then never finish.
  def hold(client, events)
    read_request_head(client)
    events << :request
    sleep
  end

  def slow_body(client, events)
    read_request_head(client)
    events << :request
    client.write("HTTP/1.1 200 OK\r\nContent-Type: application/json\r\nContent-Length: 100\r\n\r\n0123456789")
    client.flush
    sleep
  end

  {
    "FaradayTransport" => ->(**timeouts) { HttpTransport::FaradayTransport.new(**timeouts) },
    "HttpRbTransport" => ->(**timeouts) { HttpTransport::HttpRbTransport.new(**timeouts) }
  }.each do |name, build|
    context "with #{name}" do
      let(:transport) { build.call(open_timeout: 1, read_timeout: 0.5) }

      def requests_received(events)
        count = 0
        count += 1 while events.pop(timeout: 0) == :request
        count
      end

      it "raises Timeout when the server accepts and sends nothing, after a single request" do
        resources = nil
        elapsed = nil
        with_server(method(:hold)) do |server|
          resources = server
          started = monotonic_now
          expect { transport.get("http://127.0.0.1:#{server[:port]}/v1/forecast", params: { "a" => "1" }, headers: {}) }
            .to raise_error(HttpTransport::Timeout)
          elapsed = monotonic_now - started
          expect(requests_received(server[:events])).to eq(1)
        end

        report("#{name}: timeout without response", elapsed, resources[:port])
        expect(elapsed).to be_between(0.4, 2.0)
        expect_cleaned_up(resources)
      end

      it "raises Timeout when the body stalls after the headers, without a partial response" do
        resources = nil
        elapsed = nil
        result = nil
        with_server(method(:slow_body)) do |server|
          resources = server
          started = monotonic_now
          expect { result = transport.get("http://127.0.0.1:#{server[:port]}/v1/forecast", params: {}, headers: {}) }
            .to raise_error(HttpTransport::Timeout)
          elapsed = monotonic_now - started
          expect(requests_received(server[:events])).to eq(1)
        end

        report("#{name}: timeout in the body", elapsed, resources[:port])
        expect(result).to be_nil
        expect(elapsed).to be_between(0.4, 2.0)
        expect_cleaned_up(resources)
      end

      it "raises ConnectionFailed when nothing listens on the port" do
        # Small race: between closing this server and connecting, another process
        # could take the port. Interference there is a test-setup problem, not a
        # transport failure.
        probe = TCPServer.new("127.0.0.1", 0)
        port = probe.addr[1]
        probe.close
        WebMock.disable_net_connect!(allow: "127.0.0.1:#{port}")

        started = monotonic_now
        expect { transport.get("http://127.0.0.1:#{port}/v1/forecast", params: {}, headers: {}) }
          .to raise_error(HttpTransport::ConnectionFailed)
        report("#{name}: connection refused", monotonic_now - started, port)
      ensure
        WebMock.disable_net_connect!
      end
    end
  end
end

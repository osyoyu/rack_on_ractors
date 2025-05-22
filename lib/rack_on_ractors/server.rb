# frozen_string_literal: true

require 'rack'
require 'socket'

require_relative './http_parser'

module RackOnRactors
  class Server
    include Socket::Constants

    RFC9110_REASON_PHRASES = {
      100 => "Continue",
      101 => "Switching Protocols",
      200 => "OK",
      201 => "Created",
      202 => "Accepted",
      203 => "Non-Authoritative Information",
      204 => "No Content",
      205 => "Reset Content",
      206 => "Partial Content",
      300 => "Multiple Choices",
      301 => "Moved Permanently",
      302 => "Found",
      303 => "See Other",
      304 => "Not Modified",
      305 => "Use Proxy",
      307 => "Temporary Redirect",
      308 => "Permanent Redirect",
      400 => "Bad Request",
      401 => "Unauthorized",
      402 => "Payment Required",
      403 => "Forbidden",
      404 => "Not Found",
      405 => "Method Not Allowed",
      406 => "Not Acceptable",
      407 => "Proxy Authentication Required",
      408 => "Request Timeout",
      409 => "Conflict",
      410 => "Gone",
      411 => "Length Required",
      412 => "Precondition Failed",
      413 => "Content Too Large",
      414 => "URI Too Long",
      415 => "Unsupported Media Type",
      416 => "Range Not Satisfiable",
      417 => "Expectation Failed",
      421 => "Misdirected Request",
      422 => "Unprocessable Content",
      426 => "Upgrade Required",
      500 => "Internal Server Error",
      501 => "Not Implemented",
      502 => "Bad Gateway",
      503 => "Service Unavailable",
      504 => "Gateway Timeout",
      505 => "HTTP Version Not Supported",
    }.freeze

    def initialize(bind_address = "127.0.0.1", port = 8080)
      @bind_address = bind_address
      @port = port

      @app = Rack::Builder.parse_file("./config.ru")
      raise "app is not shareable" if !Ractor.shareable?(@app)
    end

    def start
      socket = Socket.new(AF_INET, SOCK_STREAM, 0)
      socket.setsockopt(SOL_SOCKET, SO_REUSEADDR, true)
      sockaddr = Socket.pack_sockaddr_in(@port, @bind_address)
      socket.bind(sockaddr)
      socket.listen(10) # backlog
      puts "Listening on #{@bind_address}:#{@port}"

      loop do
        connn, _ = socket.accept # choose awkward name to avoid shadowing

        # Make sure @app does not get copied on Ractor.new
        raise if !Ractor.shareable?(@app)
        Ractor.new(@app) do |app|
          conn = Ractor.receive
          request = HttpParser.parse_request(conn)
          env = request.to_env

          begin
            res = app.call(env)
          rescue => e
            error_message = [
              "#{e.class}: #{e.message}",
              e.backtrace&.map { |line| "\tfrom #{line}" }&.join("\n")
            ].join("\n")
            puts error_message
            res = [500, {"Content-Type" => "text/plain"}, ["Error\n"]]
          end

          status_code = res[0]
          reason_phrase = RFC9110_REASON_PHRASES[status_code] || "Unknown"

          body = res[2][0]
          conn.puts "HTTP/1.1 #{status_code} #{reason_phrase}\r\n"
          conn.puts "Content-Length: #{body.bytesize}\r\n"
          conn.puts "Connection: Close\r\n"
          res[1].each do |header_name, header_body|
            conn.puts "#{header_name}: #{header_body}"
          end
          conn.puts "\r\n"
          conn.puts body
          conn.close

          nil # reduce implicit copy on #take
        end.send(connn, move: true)
      end
    ensure
      socket.close if defined?(socket)
    end
  end
end

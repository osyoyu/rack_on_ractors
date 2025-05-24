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

    def initialize(bind_address = "127.0.0.1", port = 8080, call_make_shareable: false)
      @bind_address = bind_address
      @port = port

      @app = Rack::Builder.parse_file("./config.ru")

      # When app_make_shareable: true, app will be deep frozen in attempt to
      # make it Ractor shareable.
      # This comes useful when multiple middleware are configured
      # (Rack::Builder will not freeze middlewares on its own).
      # Note: the app may not be made shareable, even if this option is specified.
      Ractor.make_shareable(@app) if call_make_shareable
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

          conn.write "HTTP/1.1 #{status_code} #{reason_phrase}\r\n"

          # Send headers
          headers = res[1]
          headers.each do |header_name, header_body|
            conn.write "#{header_name}: #{header_body}\r\n"
          end

          chunked = headers["Transfer-Encoding"] == "chunked" # ?

          # Send body
          body = res[2]
          if !chunked
            body_str = String.new
            body.each { body_str << it }

            conn.write "Content-Length: #{body_str.bytesize}\r\n"
            conn.write "Connection: Close\r\n" # no keepalive impl (yet)
            conn.write "\r\n"

            conn.write body_str
          else
            conn.write "\r\n"

            body.each do |chunk|
              conn.write chunk.bytesize.to_s(16) + "\r\n"
              conn.write chunk
              conn.write "\r\n"
            end

            conn.write "0" + "\r\n\r\n"
          end

          conn.close
          if body.respond_to?(:close)
            body.close
          end

          nil # reduce implicit copy on #take
        end.send(connn, move: true)
      end
    ensure
      socket.close if defined?(socket)
    end
  end
end

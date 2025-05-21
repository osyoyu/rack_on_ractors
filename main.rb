# frozen_string_literal: true

require 'rack'
require 'socket'

class Server
  include Socket::Constants

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
        request = Request.from_connection(conn)
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

        body = res[2][0]
        conn.puts "HTTP/1.1 200 OK\r\n"
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

  class Request
    class << self
      def from_connection(conn)
        request_line = conn.gets("\r\n")
        parsed_request_line = parse_request_line(request_line)
        new(parsed_request_line[:method], parsed_request_line[:request_target], parsed_request_line[:http_version])
      end

      private def parse_request_line(request_line)
        method, request_target, http_version = request_line.split(" ")
        { method:, request_target:, http_version: }
      end
    end

    def initialize(method, request_target, http_version)
      @method = method
      @request_target = request_target
      @http_version = http_version
    end

    def to_env
      {
        "REQUEST_METHOD" => @method.upcase,
        "SERVER_NAME" => "example.org",
        "SERVER_PORT" => "80",
        "SERVER_PROTOCOL" => @http_version,
        "QUERY_STRING" => "",
        "PATH_INFO" => @request_target,
        "rack.url_scheme" => "http",
        "HTTPS" => "off",
        "SCRIPT_NAME" => "",
      }
    end
  end
end

Server.new.start

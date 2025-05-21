# frozen_string_literal: true

module RackOnRactors
  module HttpParser
    class << self
      def parse_request(io)
        request_line = io.gets("\r\n").chomp
        method, request_target, version = request_line.split(' ', 3)

        headers = {}
        while line = io.gets("\r\n")
          line = line.chomp
          break if line.empty?

          header_name, header_value = line.split(':', 2)
          headers[header_name] = header_value.split
        end

        body =
          if length = headers['Content-Length'] # TODO: match any case
            io.read(length.to_i)
          else
            nil
          end

        Request.new(method, request_target, version, headers, body)
      end
    end

    class Request
      def initialize(method, request_target, http_version, headers, body)
        @method = method
        @request_target = request_target
        @http_version = http_version
        @headers = {}
        @body = nil
      end

      # Aims to implement the Rack spec.
      # https://github.com/rack/rack/blob/v3.1.15/SPEC.rdoc#label-The+Environment
      def to_env
        env = {}

        path, query = @request_target.split('?')
        query ||= ''

        env['REQUEST_METHOD']  = @method.upcase
        env['SCRIPT_NAME'] = ''
        env['PATH_INFO'] = path
        env['QUERY_STRING'] = query
        env['SERVER_NAME'] = 'localhost'
        env['SERVER_PROTOCOL'] = @http_version
        env['SERVER_PORT'] = '80'

        # Map headers: CONTENT_TYPE, CONTENT_LENGTH unprefixed; others prefixed with HTTP_
        @headers.each do |name, value|
          rack_name = name.upcase.gsub('-', '_')
          if rack_name == 'CONTENT_TYPE' || rack_name == 'CONTENT_LENGTH'
            env[rack_name] = value
          else
            env["HTTP_#{rack_name}"] = value
          end
        end

        env
      end
    end
  end
end

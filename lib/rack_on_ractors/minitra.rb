# frozen_string_literal: true

def proc2src(proc)
  # Proc#source_location in Ruby 3.5+ returns a 5-tuple
  path, start_line, start_col, end_line, end_col = proc.source_location
  lines = File.open(path).each_line.drop(start_line - 1).take(end_line - start_line + 1)
  lines[0] = lines[0][start_col..-1]
  lines[-1] = lines[-1][0...end_col]

  # remove { } / do-end
  if lines[0] == '{'
    lines[0] = lines[0][1..-1] # {
    lines[-1] = lines[-1][0..-2] # }
  else
    lines[0] = lines[0][2..-1] # do
    lines[-1] = lines[-1][0..-4] # end
  end

  lines.join
end

def path_to_method_name(path)
  path.gsub('/', '__')
end

module RackOnRactors
  module Minitra
    class Base
      class << self
        def get(path, &block)
          define_handler('get', path, &block)
        end

        def post(path, &block)
          define_handler('post', path, &block)
        end

        def put(path, &block)
          define_handler('put', path, &block)
        end

        def delete(path, &block)
          define_handler('delete', path, &block)
        end

        private def define_handler(method, path, &block)
          # It's illegal to carry Procs across Ractors, so we resort to
          # stringifying Procs here
          #
          # Could be resolved in https://bugs.ruby-lang.org/issues/17159 .
          self.class_eval(<<~__RUBY__)
            def #{method}__#{path_to_method_name(path)}(headers, body)
              proc { #{proc2src(block)} }.call(headers, body)
            end
          __RUBY__
        end
      end

      def call(env)
        method = env['REQUEST_METHOD'].downcase
        path = env['PATH_INFO']

        request_headers = {}
        env.each do |key, value|
          next if !(key == 'CONTENT_TYPE' || key == 'CONTENT_LENGTH' || key.start_with?('HTTP_'))
          request_headers[key.delete_prefix('HTTP_').downcase.gsub('_', '-')] = value
        end

        request_body = env['rack.input']

        res = self.send("#{method}__#{path_to_method_name(path)}", request_headers, request_body)

        response_headers = {}
        if res.is_a?(Stream)
          response_headers['Transfer-Encoding'] = 'chunked'
          response_headers['Content-Type'] = 'text/event-stream'
          response_body = res
        else
          response_body = [res]
        end

        [200, response_headers, response_body]
      end

      def stream(&block)
        Stream.new(&block)
      end
    end

    class Stream
      def initialize(&producer_block)
        @producer_block = producer_block
        @consumer_block = nil
      end

      def each(&consumer_block)
        @consumer_block = consumer_block
        @producer_block.call(self)
      end

      def write(data)
        @consumer_block.call(data.to_s)
        data.to_s.bytesize
      end
    end
  end
end

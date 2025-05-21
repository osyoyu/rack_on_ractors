# frozen_string_literal: true

require 'rack_on_ractors'

require 'erb'
require 'trilogy'

class App < RackOnRactors::Minitra::Base
  get "/" do
    client = Trilogy.new(host: "127.0.0.1", port: 3306, username: "root")
    result = client.query("select 1")
    result.each_hash do |a|
      return "hello world #{a}\n"
    end
  end

  get "/2" do
    # We must create and specify a binding here since
    # Object::TOPLEVEL_BINDING is not accessible from non-main Ractors
    b = binding
    b.local_variable_set(:user, "osyoyu")
    erb = ERB.new(File.read("./index.html.erb"), trim_mode: '-')
    erb.result(b)
  end
end

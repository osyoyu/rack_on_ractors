# frozen_string_literal: true

require 'rack_on_ractors/minitra'

class App < RackOnRactors::Minitra::Base
  get "/longlonglong" do
    "hello! " * 1000000
  end
end

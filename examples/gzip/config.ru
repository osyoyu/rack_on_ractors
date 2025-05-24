require_relative './app'

use Rack::ContentLength

# Freeze constants used from Rack::Deflater.
#
# Rack wants to keep constants unfrozen for compatibility
# https://github.com/rack/rack/pull/2275
Ractor.make_shareable Rack::Utils::STATUS_WITH_NO_ENTITY_BODY
use Rack::Deflater

run App.new.freeze

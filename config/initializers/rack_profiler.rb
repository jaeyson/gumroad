# frozen_string_literal: true

require "rack-mini-profiler"

Rack::MiniProfilerRails.initialize!(Rails.application)

Rack::MiniProfiler.config.authorization_mode = :allow_authorized
Rack::MiniProfiler.config.enable_advanced_debugging_tools = true

Rack::MiniProfiler.config.skip_paths = [
  /#{ASSET_DOMAIN}/,
]

Rack::MiniProfiler.config.start_hidden = true

Rack::MiniProfiler.config.storage_instance = Rack::MiniProfiler::RedisStore.new(
  connection: $redis,
  expires_in: 1.hour.in_seconds,
)

Rack::MiniProfiler.config.user_provider = ->(env) do
  request = ActionDispatch::Request.new(env)
  id = request.cookies['_gumroad_guid'] || request.remote_ip || "unknown"

  Digest::SHA256.hexdigest(id.to_s)
end

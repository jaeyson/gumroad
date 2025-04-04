# frozen_string_literal: true

require "rack-mini-profiler"

Rack::MiniProfilerRails.initialize!(Rails.application)

Rack::MiniProfiler.config.authorization_mode = :allow_authorized
Rack::MiniProfiler.config.enable_advanced_debugging_tools = true

Rack::MiniProfiler.config.skip_paths = [
  /#{ASSET_DOMAIN}/o,
]

Rack::MiniProfiler.config.start_hidden = true

Rack::MiniProfiler.config.storage_instance = Rack::MiniProfiler::RedisStore.new(
  connection: $redis,
  expires_in: 1.hour.in_seconds,
)

Rack::MiniProfiler.config.user_provider = ->(env) do
  request = ActionDispatch::Request.new(env)
  id = request.cookies["_gumroad_guid"] || request.remote_ip || "unknown"

  Digest::SHA256.hexdigest(id.to_s)
end

module Rack
  class MiniProfiler
    def inject_profiler(env, status, headers, body)
      # mini profiler is meddling with stuff, we can not cache cause we will get incorrect data
      # Rack::ETag has already inserted some nonesense in the chain
      content_type = headers["Content-Type"]

      if config.disable_caching
        headers.delete("ETag")
        headers.delete("Date")
      end

      headers["X-MiniProfiler-Original-Cache-Control"] = headers["Cache-Control"] unless headers["Cache-Control"].nil?
      headers["Cache-Control"] = "#{"no-store, " if config.disable_caching}must-revalidate, private, max-age=0"

      # inject header
      if headers.is_a? Hash
        headers["X-MiniProfiler-Debug-1-Inject-Profiler"] = {
          inject_js: current.inject_js,
          content_type: content_type,
          headers: headers,
        }.to_json
        headers["X-MiniProfiler-Ids"] = ids_comma_separated(env)
        headers["X-MiniProfiler-Flamegraph-Path"] = flamegraph_path(env) if current.page_struct[:has_flamegraph]
      end

      if !current.inject_js && content_type.include?("text/html")
        response = Rack::Response.new([], status, headers)
        script   = self.get_profile_script(env, headers)
        response.add_header("X-MiniProfiler-Debug-2-Trying-To-Inject-JS", "yes")
        response.add_header("X-MiniProfiler-Debug-3-Script-Value", script)

        if String === body
          response.write inject(body, script, response)
        else
          body.each { |fragment| response.write inject(fragment, script, response) }
        end
        body.close if body.respond_to? :close
        response.finish
      else
        response = Rack::Response.new([], status, headers)
        if String === body
          s = body.to_s
          response.write s
          response.add_header("X-MiniProfiler-Debug-4-content", s[0, 100])
        else
          body.each.with_index do |fragment, index|
            s = fragment.to_s
            response.add_header("X-MiniProfiler-Debug-4-content-#{index}", s[0, 100])
            response.write s
          end
        end
        body.close if body.respond_to? :close
        response.finish
      end
    end

    def inject(fragment, script, response)
      random_id = SecureRandom.uuid
      # find explicit or implicit body
      index = fragment.rindex(/<\/body>/i) || fragment.rindex(/<\/html>/i)
      if index
        response.add_header("X-MiniProfiler-Debug-4-Inject-#{random_id}", "yes")
        # if for whatever crazy reason we dont get a utf string,
        #   just force the encoding, no utf in the mp scripts anyway
        if script.respond_to?(:encoding) && script.respond_to?(:force_encoding)
          script = script.force_encoding(fragment.encoding)
        end

        safe_script = script
        if script.respond_to?(:html_safe)
          safe_script = script.html_safe
        end

        fragment.insert(index, safe_script)
      else
        response.add_header("X-MiniProfiler-Debug-4-Inject-#{random_id}", "no")
        fragment
      end
    end
  end
end

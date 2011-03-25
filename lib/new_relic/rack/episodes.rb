require 'rack'

module NewRelic::Rack
  class Episodes
    def initialize(app, options = {})
      @app = app
    end
      
    # method required by Rack interface
    def call(env)
      call! env
    end

      # thread safe version using shallow copy of env
      def call!(env)
        @env = env.dup
        status, @headers, response = @app.call(@env)      
        if should_instrument?(@headers)
          @headers.delete('Content-Length')
          response = Rack::Response.new(
            autoinstrument_source(response.respond_to?(:body) ? response.body : response),
            status,
            @headers
          )
          response.finish
          response.to_a
        else
          [status, @headers, response]
        end
      end
      
      def should_instrument?(headers)
        headers["Content-Type"] && headers["Content-Type"].include?("text/html")
      end
      
    def autoinstrument_source(source)
      source.join! if source.is_a? Array
      if source =~ /(.*<html>)(.*)(<body)(.*)(<\/body>.*<\/html>.*)/mi
        newrelic_header = NewRelic::Agent.browser_timing_header
        newrelic_footer = NewRelic::Agent.browser_timing_footer

        source = $1
        after_html = $2
          
        body_tag = $3
        body = $4
        close = $5
          
        if $2 =~ /(.*)(<head>)(.*)/mi
          source << $1 << $2 << newrelic_header << $3
        else
          source << newrelic_header << after_html          
        end
          
        source << body_tag << body << newrelic_footer << close
      end
      source
    end
  end
end
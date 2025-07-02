# Helper to manage nghttpd server for tests
module NghttpdHelper
  @@process : Process? = nil
  @@started = false
  
  # Start nghttpd if we're not in docker-compose environment
  def self.ensure_running
    return if ENV["TEST_NGHTTPD_URL"]? # Already available via docker-compose
    return if @@started
    
    start_local_nghttpd
  end
  
  private def self.start_local_nghttpd
    # Check if nghttpd is installed
    unless system("which nghttpd > /dev/null 2>&1")
      puts "WARNING: nghttpd not found. HTTP/2 tests will fail."
      puts "Install with: apt-get install nghttp2-server"
      return
    end
    
    # Create certificates if needed
    cert_dir = "/tmp/nghttpd_test_certs"
    Dir.mkdir_p(cert_dir)
    
    cert_path = File.join(cert_dir, "cert.pem")
    key_path = File.join(cert_dir, "key.pem")
    
    unless File.exists?(cert_path) && File.exists?(key_path)
      # Generate self-signed certificate
      system(%Q{
        openssl req -x509 -newkey rsa:2048 \
          -keyout "#{key_path}" -out "#{cert_path}" \
          -days 365 -nodes \
          -subj "/C=US/ST=State/L=City/O=Test/CN=localhost" \
          2>/dev/null
      })
    end
    
    # Create a simple HTML file to serve
    html_dir = "/tmp/nghttpd_test_html"
    Dir.mkdir_p(html_dir)
    File.write(File.join(html_dir, "index.html"), <<-HTML)
      <html>
        <head>
          <title>h2o HTTP/2 Test</title>
        </head>
        <body>
          <h1>h2o HTTP/2 Test Server</h1>
          <p>This is a test page for HTTP/2 integration tests.</p>
        </body>
      </html>
    HTML
    
    # Start nghttpd
    begin
      @@process = Process.new(
        "nghttpd",
        args: ["-d", "--htdocs=#{html_dir}", "4430", key_path, cert_path],
        output: Process::Redirect::Close,
        error: Process::Redirect::Close
      )
      
      # Give it time to start
      sleep 0.5.seconds
      
      # Check if it's running
      if @@process.try(&.terminated?)
        puts "ERROR: nghttpd failed to start"
        @@process = nil
      else
        @@started = true
        puts "Started local nghttpd on port 4430"
        
        # Register cleanup
        at_exit { cleanup }
      end
    rescue ex
      puts "ERROR starting nghttpd: #{ex.message}"
    end
  end
  
  def self.cleanup
    if process = @@process
      unless process.terminated?
        process.terminate
        process.wait
      end
      @@process = nil
      @@started = false
    end
  end
end

# Auto-start nghttpd when specs load
Spec.before_suite do
  NghttpdHelper.ensure_running
end
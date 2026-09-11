class Slopchan < Formula
  desc "Self-hosted imageboard for AI agents"
  homepage "https://github.com/rengwu/slopchan"
  version "0.3.1"
  license "MIT"

  on_macos do
    on_arm do
      url "https://github.com/rengwu/slopchan/releases/download/v0.3.1/slopchan_0.3.1_darwin_arm64.tar.gz"
      sha256 "fe1b4fdc9d53755de7cc2bae93c376f6d51dc2cc740674552bad940ce68ca89c"
    end
    on_intel do
      url "https://github.com/rengwu/slopchan/releases/download/v0.3.1/slopchan_0.3.1_darwin_amd64.tar.gz"
      sha256 "baddc69d87cf52b12247e62f0f98bbbc739721633acae3d26bd767e778110edd"
    end
  end

  on_linux do
    on_arm do
      url "https://github.com/rengwu/slopchan/releases/download/v0.3.1/slopchan_0.3.1_linux_arm64.tar.gz"
      sha256 "92ce254849ca87c22d6fc6a0034b05daabd7e5e41eaf9d90270e27e51b044023"
    end
    on_intel do
      url "https://github.com/rengwu/slopchan/releases/download/v0.3.1/slopchan_0.3.1_linux_amd64.tar.gz"
      sha256 "39d27be579775ca5fd731682348289f74dd21545494b9283fc1641f43f171234"
    end
  end

  def install
    bin.install "slopchan"

    # Keep data outside the versioned Cellar; pass upstream configuration through.
    (bin/"slopchan-server").write <<~SH
      #!/bin/sh
      set -eu
      umask 077
      export SLOPCHAN_DATA_DIR="${SLOPCHAN_DATA_DIR:-#{var}/slopchan}"
      export SLOPCHAN_LISTEN="${SLOPCHAN_LISTEN:-127.0.0.1:8080}"
      exec "#{opt_bin}/slopchan" "$@"
    SH
    chmod 0755, bin/"slopchan-server"
    pkgshare.install "skills/slopchan", "onboarding.md", "docs", "LICENSE", "licenses"
  end

  def post_install
    [etc/"slopchan", var/"slopchan", var/"log/slopchan"].each do |directory|
      directory.mkpath
      directory.chmod 0700
    end
  end

  def caveats
    <<~EOS
      Configure admin credentials and HTTPS before starting the service.
      For plain HTTP, explicitly set SLOPCHAN_ALLOW_INSECURE_ADMIN=true.
      Setup guide: https://github.com/rengwu/homebrew-tap#running-and-configuring
      Admin portal: https://YOUR-HOST:PORT/admin
      Create agent tokens and download .env.slopchan in the portal.

      Instance data: #{var}/slopchan
      Agent skill:   #{pkgshare}/slopchan/SKILL.md
      Run in the foreground with slopchan-server.
      Stop the server and back up the whole data directory before upgrading.
    EOS
  end

  service do
    run [opt_bin/"slopchan-server"]
    keep_alive crashed: true
    log_path var/"log/slopchan/stdout.log"
    error_log_path var/"log/slopchan/stderr.log"
  end

  test do
    require "json"
    require "net/http"

    assert_match version.to_s, shell_output("#{bin}/slopchan version")

    port = free_port
    ENV["SLOPCHAN_DATA_DIR"] = (testpath/"board data").to_s
    ENV["SLOPCHAN_LISTEN"] = "127.0.0.1:#{port}"
    ENV.delete("SLOPCHAN_TOKENS")
    ENV["SLOPCHAN_TOKEN_FILE"] = (testpath/"test token").to_s
    (testpath/"test token").write("homebrew-test-token\n")
    uri = URI("http://127.0.0.1:#{port}/api/threads")

    2.times do |iteration|
      pid = spawn bin/"slopchan-server", out: (testpath/"server.log").to_s, err: [:child, :out]
      begin
        response = nil
        100.times do
          response = Net::HTTP.get_response(uri)
          break
        rescue Errno::ECONNREFUSED
          sleep 0.1
        end
        assert_equal "200", response&.code, (testpath/"server.log").read

        if iteration.zero?
          request = Net::HTTP::Post.new(uri)
          request["Content-Type"] = "application/json"
          request.body = JSON.generate(text: "homebrew persistence check")
          unauthorized = Net::HTTP.start(uri.hostname, uri.port) { |http| http.request(request) }
          assert_equal "401", unauthorized.code
          request["Authorization"] = "Bearer homebrew-test-token"
          posted = Net::HTTP.start(uri.hostname, uri.port) { |http| http.request(request) }
          assert_equal "201", posted.code
        else
          assert_match "homebrew persistence check", response.body
          search = URI("http://127.0.0.1:#{port}/api/search?q=persistence")
          assert_equal 1, JSON.parse(Net::HTTP.get(search)).fetch("posts").length
        end
      ensure
        Process.kill "TERM", pid
        _, status = Process.wait2 pid
      end
      assert_predicate status, :success?
    end
  end
end

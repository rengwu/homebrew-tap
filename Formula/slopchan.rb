class Slopchan < Formula
  desc "Self-hosted imageboard for AI agents"
  homepage "https://github.com/rengwu/slopchan"
  version "0.3.0"
  license "MIT"

  bottle do
    root_url "https://github.com/rengwu/homebrew-tap/releases/download/slopchan-0.3.0"
    sha256 cellar: :any_skip_relocation, arm64_sonoma:  "58d53e1b7e2a02c337d0059b8d13b15984efd187a66709ec451b104bec6ca341"
    sha256 cellar: :any_skip_relocation, sequoia:       "e764e0c94c21dadfb9f3a7145e2a6b579cb454142f8685e7f85652de1d4023db"
    sha256 cellar: :any_skip_relocation, arm64_linux:   "6fa7ba7ca5ac4fdf60ba2119bdd0ea1bdbc22acdc939f7f8d55faccc5df51ae7"
    sha256 cellar: :any_skip_relocation, x86_64_linux:  "9d8f5b313af69a663c3f09a39bcf208dc46ea7fcd80bcf6d1128c11eb9f7245e"
  end

  on_macos do
    on_arm do
      url "https://github.com/rengwu/slopchan/releases/download/v0.3.0/slopchan_0.3.0_darwin_arm64.tar.gz"
      sha256 "8570858ba70259b0801c0cb16ca30862e318edb1fd6b4af53b299c2235556d85"
    end
    on_intel do
      url "https://github.com/rengwu/slopchan/releases/download/v0.3.0/slopchan_0.3.0_darwin_amd64.tar.gz"
      sha256 "8bc6f2ac7e30507dc637fa7a73406e6dad42fc5d51b76375f1b72e00720df557"
    end
  end

  on_linux do
    on_arm do
      url "https://github.com/rengwu/slopchan/releases/download/v0.3.0/slopchan_0.3.0_linux_arm64.tar.gz"
      sha256 "884181a7d84440aa318c7e14d88308d3e02839b3e0bb2331eb68a05e9bf9fb52"
    end
    on_intel do
      url "https://github.com/rengwu/slopchan/releases/download/v0.3.0/slopchan_0.3.0_linux_amd64.tar.gz"
      sha256 "a49e3c1cb311cd988286e01d77ba7aed8c5ea8fa51fa82834c8c5a49dcdcc00f"
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

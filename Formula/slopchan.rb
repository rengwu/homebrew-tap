class Slopchan < Formula
  desc "Self-hosted imageboard for AI agents"
  homepage "https://github.com/rengwu/slopchan"
  version "0.3.2"
  license "MIT"

  bottle do
    root_url "https://github.com/rengwu/homebrew-tap/releases/download/slopchan-0.3.2"
    sha256 cellar: :any_skip_relocation, arm64_sonoma: "698179f0de29cc10cb7670f62e1fb1a0169b96bb564c0d8ab765b22722e5b062"
    sha256 cellar: :any_skip_relocation, sequoia:      "70390de53c0200772f8f3419bf1c8c60a8ded28a1a361fd115319e0c3088394f"
    sha256 cellar: :any_skip_relocation, arm64_linux:  "eb38ff57f7e4203b4d9f89ee5dfa612dadd69efaef745179cfa04dfde8aa6c15"
    sha256 cellar: :any_skip_relocation, x86_64_linux: "a8103dbba8fa8c54d6fd0a925ab5d02cd992e4936d2360a8cff0d4e6d22fa8cf"
  end

  on_macos do
    on_arm do
      url "https://github.com/rengwu/slopchan/releases/download/v0.3.2/slopchan_0.3.2_darwin_arm64.tar.gz"
      sha256 "84410c349ed1ed8f61ce973c092354a9a6e5d99553b5998e80f03cfaa6a9b9af"
    end
    on_intel do
      url "https://github.com/rengwu/slopchan/releases/download/v0.3.2/slopchan_0.3.2_darwin_amd64.tar.gz"
      sha256 "79614ea9fa3cb625e91c03946c48b8ac181ab89d6aeec81a5fa21d489c4d620e"
    end
  end

  on_linux do
    on_arm do
      url "https://github.com/rengwu/slopchan/releases/download/v0.3.2/slopchan_0.3.2_linux_arm64.tar.gz"
      sha256 "83620a71055db85e48e4487072a1450225fde4b2a0676d82e3546022df5f63f9"
    end
    on_intel do
      url "https://github.com/rengwu/slopchan/releases/download/v0.3.2/slopchan_0.3.2_linux_amd64.tar.gz"
      sha256 "46ece80792d7344b06079d3da79c43369e6f47a74c59da245f97abdee200470d"
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

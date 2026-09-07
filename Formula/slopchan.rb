require "securerandom"

class Slopchan < Formula
  desc "Tiny public imageboard for AI agents"
  homepage "https://github.com/rengwu/slopchan"
  version "0.2.1"
  revision 1
  license "MIT"

  on_macos do
    on_arm do
      url "https://github.com/rengwu/slopchan/releases/download/v0.2.1/slopchan_0.2.1_darwin_arm64.tar.gz"
      sha256 "cf1b51970bf57cdc66586589e858d17dd686e7fd63c1c5bc0aa1c62a901805e3"
    end
    on_intel do
      url "https://github.com/rengwu/slopchan/releases/download/v0.2.1/slopchan_0.2.1_darwin_amd64.tar.gz"
      sha256 "ae0b2db3cb107304fa697367ecfb10ad822cfa2f0e6e0b626eb74eada2e55b88"
    end
  end

  on_linux do
    on_arm do
      url "https://github.com/rengwu/slopchan/releases/download/v0.2.1/slopchan_0.2.1_linux_arm64.tar.gz"
      sha256 "ca7390cc39c7b514c4ef30acae5596b9eb0f2c82929ff858d494512036a5c656"
    end
    on_intel do
      url "https://github.com/rengwu/slopchan/releases/download/v0.2.1/slopchan_0.2.1_linux_amd64.tar.gz"
      sha256 "e89558223b7e9ef8532ed83bf03e41162499fec0c29d4ab672e66c254ba1c81b"
    end
  end

  def install
    bin.install "slopchan"

    # Load private credentials without embedding them in the service definition.
    # Keep them in a private file, outside the versioned Cellar and service plist.
    (bin/"slopchan-server").write <<~SH
      #!/bin/sh
      set -eu
      umask 077
      export SLOPCHAN_DATA_DIR="${SLOPCHAN_DATA_DIR:-#{var}/slopchan}"
      export SLOPCHAN_LISTEN="${SLOPCHAN_LISTEN:-127.0.0.1:8080}"
      if [ -z "${SLOPCHAN_TOKENS:-}" ]; then
        SLOPCHAN_TOKENS=$(cat "${SLOPCHAN_TOKEN_FILE:-#{etc}/slopchan/tokens}")
      fi
      unset SLOPCHAN_TOKEN_FILE
      export SLOPCHAN_TOKENS
      exec "#{opt_bin}/slopchan" "$@"
    SH
    chmod 0755, bin/"slopchan-server"
    pkgshare.install "skills/slopchan", "LICENSE", "licenses"
  end

  def post_install
    [etc/"slopchan", var/"slopchan", var/"log/slopchan"].each do |directory|
      directory.mkpath
      directory.chmod 0700
    end
    token_file = etc/"slopchan/tokens"
    return if token_file.exist?

    File.open(token_file, File::WRONLY | File::CREAT | File::EXCL, 0600) do |file|
      file.puts SecureRandom.hex(32)
    end
  end

  def caveats
    <<~EOS
      Open http://127.0.0.1:8080 after starting the server.
      Posting token: #{etc}/slopchan/tokens (generated once; kept on upgrades).
      Board data:    #{var}/slopchan
      Agent skill:   #{pkgshare}/slopchan/SKILL.md

      Run in the foreground with slopchan-server.
      For LAN access: SLOPCHAN_LISTEN=0.0.0.0:8080 slopchan-server
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

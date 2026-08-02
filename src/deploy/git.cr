require "file_utils"

module Yozgat
  module Deploy
    module Git
      GITHUB_PREFIX = "https://github.com/"
      GIT_ENV       = {"GIT_TERMINAL_PROMPT" => "0"}

      def self.normalize_github_url(raw : String) : String
        t = raw.strip
        raise ArgumentError.new("repository url is required") if t.empty?
        raise ArgumentError.new("Only GitHub HTTPS URLs are supported (e.g. https://github.com/acme/site).") if t.includes?('@')
        raise ArgumentError.new("Only GitHub HTTPS URLs are supported (e.g. https://github.com/acme/site).") unless t.downcase.starts_with?(GITHUB_PREFIX)

        path = t[GITHUB_PREFIX.size..].lstrip('/').rstrip('/')
        raise ArgumentError.new("invalid repository path") if path.empty? || path.includes?("..") || path.includes?("//")

        parts = path.split('/').reject(&.empty?)
        raise ArgumentError.new("Only GitHub HTTPS URLs are supported (e.g. https://github.com/acme/site).") unless parts.size == 2

        owner = parts[0]
        repo = parts[1].ends_with?(".git") ? parts[1][0..-5] : parts[1]
        raise ArgumentError.new("invalid owner or repository name") unless segment_ok?(owner) && segment_ok?(repo)

        "#{GITHUB_PREFIX}#{owner}/#{repo}.git"
      end

      def self.authenticated_url(repo_url : String, username : String?, token : String?) : String
        user = username.try(&.strip)
        tok = token.try(&.strip)
        if user && !user.empty? && tok && !tok.empty?
          rest = repo_url.sub(/^https:\/\//, "")
          "https://#{user}:#{tok}@#{rest}"
        else
          repo_url
        end
      end

      def self.ls_remote_success?(url : String, ref : String? = nil) : Bool
        args = ["ls-remote", url]
        args << ref if ref
        Process.run("git", args, output: Process::Redirect::Close, error: Process::Redirect::Close, env: GIT_ENV).success?
      end

      def self.ls_remote_output(url : String, ref : String) : String?
        output = IO::Memory.new
        stderr = IO::Memory.new
        ok = Process.run(
          "git",
          ["ls-remote", url, ref],
          output: output,
          error: stderr,
          env: GIT_ENV,
        ).success?
        ok ? output.to_s : nil
      end

      def self.resolve_branch_head(url : String, branch : String) : String
        ref = "refs/heads/#{branch}"
        stdout = ls_remote_output(url, ref)
        raise ArgumentError.new("Branch \"#{branch}\" not found on the repository.") unless stdout

        line = stdout.each_line.find { |l| !l.strip.empty? }
        raise ArgumentError.new("Branch \"#{branch}\" not found on the repository.") unless line

        hash = line.split.first
        raise ArgumentError.new("could not parse git ls-remote output") unless hash
        raise ArgumentError.new("unexpected commit hash from git ls-remote") unless hash.matches?(/^[0-9a-fA-F]{7,}$/)

        hash
      end

      def self.list_branches(url : String) : Array(String)
        output = IO::Memory.new
        stderr = IO::Memory.new
        ok = Process.run(
          "git",
          ["ls-remote", "--heads", url],
          output: output,
          error: stderr,
          env: GIT_ENV,
        ).success?
        unless ok
          msg = stderr.to_s.strip
          msg = "could not list branches" if msg.empty?
          raise ArgumentError.new(msg)
        end

        branches = [] of String
        output.to_s.each_line do |line|
          t = line.strip
          next if t.empty?
          parts = t.split('\t', limit: 2)
          next unless parts.size == 2

          ref = parts[1]
          next unless ref.starts_with?("refs/heads/")

          name = ref["refs/heads/".size..]
          branches << name if name && branch_ref_ok?(name)
        end

        raise ArgumentError.new("no branches found on the repository") if branches.empty?

        branches.sort do |a, b|
          rank = ->(name : String) {
            case name
            when "main"   then 0
            when "master" then 1
            else               2
            end
          }
          cmp = rank.call(a) <=> rank.call(b)
          cmp == 0 ? a <=> b : cmp
        end
      end

      def self.branch_ref_ok?(branch : String) : Bool
        !branch.empty? && branch.size <= 128 &&
          branch.chars.all? { |c| c.alphanumeric? || c == '-' || c == '_' || c == '/' }
      end

      def self.clone_and_checkout(
        repo_url : String,
        username : String?,
        token : String?,
        dest : String,
        commit_hash : String,
      ) : Nil
        FileUtils.rm_rf(dest) if Dir.exists?(dest)
        url = authenticated_url(repo_url, username, token)

        run_git!(["clone", "--no-checkout", url, dest], "git clone")
        run_git_in!(dest, ["fetch", "--depth", "1", "origin", commit_hash], "git fetch")
        run_git_in!(dest, ["checkout", "FETCH_HEAD"], "git checkout")
      end

      private def self.run_git!(args : Array(String), label : String) : Nil
        stderr = IO::Memory.new
        unless Process.run("git", args, output: Process::Redirect::Close, error: stderr, env: GIT_ENV).success?
          raise "#{label} failed: #{stderr.to_s.strip}"
        end
      end

      private def self.run_git_in!(dest : String, args : Array(String), label : String) : Nil
        stderr = IO::Memory.new
        unless Process.run("git", args, chdir: dest, output: Process::Redirect::Close, error: stderr, env: GIT_ENV).success?
          raise "#{label} failed: #{stderr.to_s.strip}"
        end
      end

      private def self.segment_ok?(s : String) : Bool
        !s.empty? && s.chars.all? { |c| c.alphanumeric? || c == '.' || c == '-' || c == '_' }
      end
    end
  end
end

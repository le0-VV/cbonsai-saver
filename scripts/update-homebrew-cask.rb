#!/usr/bin/env ruby
# frozen_string_literal: true

require "rubygems/version"

abort "Usage: #{$PROGRAM_NAME} VERSION SHA256" unless ARGV.length == 2

version, sha256 = ARGV
abort "Invalid stable release version: #{version}" unless version.match?(/\A\d+\.\d+\.\d+\z/)
abort "Invalid release SHA-256: #{sha256}" unless sha256.match?(/\A[0-9a-f]{64}\z/)

repo_root = File.expand_path("..", __dir__)
cask_path = File.join(repo_root, "Casks/cbonsai-saver.rb")
cask = File.binread(cask_path)
cask_metadata = cask.match(/^  version "([^"]+)"\n  sha256 "([0-9a-f]{64})"$/)
abort "Unable to find one current cask version and SHA-256" unless cask_metadata

current_version = cask_metadata[1]
current_sha256 = cask_metadata[2]
incoming_version = Gem::Version.new(version)
installed_version = Gem::Version.new(current_version)

abort "Refusing to downgrade cask from #{current_version} to #{version}" if incoming_version < installed_version
if incoming_version == installed_version && sha256 != current_sha256
  abort "Refusing checksum change for existing cask version #{version}"
end

def replace_once(path, pattern, description)
  content = File.binread(path)
  matches = content.to_enum(:scan, pattern).map { Regexp.last_match }
  abort "Expected one #{description} in #{path}, found #{matches.length}" unless matches.length == 1

  updated = content.sub(pattern) { yield Regexp.last_match }
  File.binwrite(path, updated) unless updated == content
end

replace_once(
  cask_path,
  /^  version "[^"]+"\n  sha256 "[0-9a-f]{64}"$/,
  "cask version and SHA-256",
) { "  version \"#{version}\"\n  sha256 \"#{sha256}\"" }

replace_once(
  File.join(repo_root, "scripts/package-release.sh"),
  /^version="\$\{1:-[^}]+\}"$/,
  "default release version",
) { "version=\"\${1:-#{version}}\"" }

replace_once(
  File.join(repo_root, ".github/workflows/ci.yml"),
  /(?<prefix>          - arch: arm64\n            release_version: )[^\n]+(?<middle>\n            runner: macos-15\n            artifact: )cbonsai-saver-[^\n]+\.zip/,
  "arm64 CI release entry",
) do |match|
  "#{match[:prefix]}#{version}#{match[:middle]}cbonsai-saver-#{version}.zip"
end

homebrew_doc_path = File.join(repo_root, "HOMEBREW.md")
replace_once(
  homebrew_doc_path,
  %r{\./scripts/package-release\.sh \d+\.\d+\.\d+ arm64},
  "documented arm64 package command",
) { "./scripts/package-release.sh #{version} arm64" }
replace_once(
  homebrew_doc_path,
  %r{build/release/artifacts/cbonsai-saver-\d+\.\d+\.\d+\.zip},
  "documented arm64 release archive",
) { "build/release/artifacts/cbonsai-saver-#{version}.zip" }

puts "Updated Homebrew release metadata to #{version} (#{sha256})."

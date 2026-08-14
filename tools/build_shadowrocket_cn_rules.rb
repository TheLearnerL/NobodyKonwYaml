#!/usr/bin/env ruby
# frozen_string_literal: true

require "digest"
require "fileutils"
require "open-uri"
require "optparse"
require "time"
require "yaml"

PROFILES = {
  "strict" => {
    source: "https://github.com/v2fly/domain-list-community/releases/latest/download/dlc.dat_plain.yml",
    checksum: "https://github.com/v2fly/domain-list-community/releases/latest/download/dlc.dat_plain.yml.sha256sum",
    source_format: :v2fly_yaml,
    list_name: "geolocation-cn",
    begin_marker: "# BEGIN GENERATED: V2Fly geolocation-cn",
    end_marker: "# END GENERATED: V2Fly geolocation-cn"
  },
  "broad" => {
    source: "https://raw.githubusercontent.com/MetaCubeX/meta-rules-dat/667c61b40dc4aae6d0e82c7a80b34f96a36102a3/geo/geosite/cn.list",
    expected_sha256: "1de88bc8a57adbd6aa236c281d1a3b18f557a5934ca20b234747068543907b8d",
    source_format: :metacubex_domain_text,
    list_name: "geosite-cn",
    upstream_license: "GPL-3.0; https://github.com/MetaCubeX/meta-rules-dat/blob/master/LICENSE",
    begin_marker: "# BEGIN GENERATED: MetaCubeX geosite-cn broad",
    end_marker: "# END GENERATED: MetaCubeX geosite-cn broad"
  }
}.freeze

def read_location(location)
  uri = URI.parse(location)
  return URI.open(uri, "rb", &:read) if %w[http https].include?(uri.scheme)

  File.binread(location)
rescue URI::InvalidURIError
  File.binread(location)
end

def atomic_write(path, content)
  FileUtils.mkdir_p(File.dirname(File.expand_path(path)))
  temporary = "#{path}.tmp.#{Process.pid}"
  File.binwrite(temporary, content)
  File.rename(temporary, path)
ensure
  File.delete(temporary) if temporary && File.exist?(temporary)
end

options = {
  profile: "strict",
  source: nil,
  source_label: nil,
  list_name: nil,
  checksum: nil,
  expected_sha256: nil,
  rules_output: nil,
  config: nil,
  remote_url: nil
}

parser = OptionParser.new do |opts|
  opts.banner = "Usage: build_shadowrocket_cn_rules.rb [options]"
  opts.on("--profile NAME", PROFILES.keys, "Rule profile: strict or broad (default: strict)") do |value|
    options[:profile] = value
  end
  opts.on("--source PATH_OR_URL", "Override the profile's source") { |value| options[:source] = value }
  opts.on("--source-label TEXT", "Source label stored in generated comments") { |value| options[:source_label] = value }
  opts.on("--checksum PATH_OR_URL", "Optional SHA-256 checksum file") { |value| options[:checksum] = value }
  opts.on("--expected-sha256 HEX", "Require an exact source SHA-256 digest") do |value|
    options[:expected_sha256] = value
  end
  opts.on("--list NAME", "Override the V2Fly list name") { |value| options[:list_name] = value }
  opts.on("--rules-output PATH", "Write a remote-ready Shadowrocket RULE-SET file") do |value|
    options[:rules_output] = value
  end
  opts.on("--config PATH", "Replace the generated block in a Shadowrocket config") do |value|
    options[:config] = value
  end
  opts.on("--remote-url HTTPS_URL", "Use an approved remote RULE-SET in the config instead of embedding rules") do |value|
    options[:remote_url] = value
  end
end
parser.parse!

if options[:rules_output].nil? && options[:config].nil?
  warn parser
  abort "At least one of --rules-output or --config is required"
end
abort "--remote-url requires --config" if options[:remote_url] && options[:config].nil?
abort "Remote delivery is currently supported only for the broad profile" if options[:remote_url] && options[:profile] != "broad"

if options[:remote_url]
  begin
    remote_uri = URI.parse(options[:remote_url])
    unless remote_uri.scheme == "https" && remote_uri.host && !options[:remote_url].include?(",")
      abort "--remote-url must be a valid HTTPS URL without commas"
    end
  rescue URI::InvalidURIError
    abort "--remote-url must be a valid HTTPS URL without commas"
  end
end

profile = PROFILES.fetch(options[:profile])
source = options[:source] || profile.fetch(:source)
list_name = options[:list_name] || profile.fetch(:list_name)

checksum_location = options[:checksum]
checksum_location ||= profile[:checksum] if source == profile[:source]
expected_sha256 = options[:expected_sha256]
expected_sha256 ||= profile[:expected_sha256] if source == profile[:source]
if source != profile[:source] && checksum_location.nil? && expected_sha256.nil?
  abort "A custom source requires --checksum or --expected-sha256"
end
if source != profile[:source] && options[:source_label].nil?
  abort "A custom source requires --source-label for provenance metadata"
end

source_data = read_location(source)
source_sha256 = Digest::SHA256.hexdigest(source_data)

if checksum_location
  checksum_data = read_location(checksum_location)
  checksum_sha256 = checksum_data[/\b[0-9a-fA-F]{64}\b/]
  abort "Checksum file does not contain a SHA-256 digest" unless checksum_sha256
  abort "SHA-256 mismatch: expected #{checksum_sha256}, got #{source_sha256}" unless checksum_sha256.casecmp?(source_sha256)
end

if expected_sha256
  abort "Expected SHA-256 must be 64 hexadecimal characters" unless expected_sha256.match?(/\A[0-9a-fA-F]{64}\z/)
  abort "SHA-256 mismatch: expected #{expected_sha256}, got #{source_sha256}" unless expected_sha256.casecmp?(source_sha256)
end

converted = []
skipped = []

case profile.fetch(:source_format)
when :v2fly_yaml
  document = YAML.safe_load(source_data, permitted_classes: [], permitted_symbols: [], aliases: false)
  entry = document.fetch("lists").find { |candidate| candidate["name"] == list_name }
  abort "List not found: #{list_name}" unless entry

  entry.fetch("rules").each do |raw_rule|
    rule_without_attributes = raw_rule.split(":@", 2).first
    type, value = rule_without_attributes.split(":", 2)

    case type
    when "domain"
      converted << "DOMAIN-SUFFIX,#{value}"
    when "full"
      converted << "DOMAIN,#{value}"
    else
      skipped << raw_rule
    end
  end
when :metacubex_domain_text
  source_data.encode("UTF-8").lines(chomp: true).each_with_index do |raw_rule, index|
    rule = raw_rule.strip
    next if rule.empty? || rule.start_with?("#")

    unless rule.start_with?("+.") && rule.length > 2 && !rule.match?(/[\s,]/)
      abort "Unsupported MetaCubeX domain rule at line #{index + 1}: #{raw_rule.inspect}"
    end

    converted << "DOMAIN-SUFFIX,#{rule.delete_prefix("+.")}"
  end
end

converted.uniq!
generated_at = Time.now.utc.iso8601
source_label = options[:source_label] || source
metadata = [
  "# Generated by tools/build_shadowrocket_cn_rules.rb; do not edit by hand.",
  "# Profile: #{options[:profile]}",
  "# Source: #{source_label}",
  "# Source SHA-256: #{source_sha256}",
  "# Source list: #{list_name}"
]
metadata << "# Upstream license: #{profile.fetch(:upstream_license)}" if profile[:upstream_license]
metadata.concat([
  "# Generated at: #{generated_at}",
  "# Converted rules: #{converted.length}; skipped non-domain rules: #{skipped.length}"
])

ruleset = (metadata + converted + [""]).join("\n") if options[:rules_output]
updated_config = nil

if options[:config]
  config = File.binread(options[:config])
  begin_marker = profile.fetch(:begin_marker)
  end_marker = profile.fetch(:end_marker)
  begin_count = config.scan(begin_marker).length
  end_count = config.scan(end_marker).length
  abort "Config must contain exactly one generated marker pair" unless begin_count == 1 && end_count == 1

  if options[:remote_url]
    config_metadata = [
      "# Generated by tools/build_shadowrocket_cn_rules.rb; do not edit by hand.",
      "# Profile: #{options[:profile]}",
      "# Delivery: remote",
      "# Source list: #{list_name}",
      "# Rule URL: #{options[:remote_url]}"
    ]
    delivered_rules = ["RULE-SET,#{options[:remote_url]},DIRECT"]
  else
    prefix = config.split(begin_marker, 2).first
    existing_direct_rules = prefix.lines(chomp: true).select { |line| line.end_with?(",DIRECT") }.to_h { |line| [line, true] }
    embedded = converted.reject { |rule| existing_direct_rules["#{rule},DIRECT"] }
    config_metadata = metadata + [
      "# Delivery: embedded",
      "# Embedded rules: #{embedded.length}; manual DIRECT duplicates omitted: #{converted.length - embedded.length}"
    ]
    delivered_rules = embedded.map { |rule| "#{rule},DIRECT" }
  end
  generated_block = ([begin_marker] + config_metadata + delivered_rules + [end_marker]).join("\n")
  marker_pattern = /#{Regexp.escape(begin_marker)}.*?#{Regexp.escape(end_marker)}/m
  updated_config = config.sub(marker_pattern, generated_block)
  unless updated_config.include?(generated_block) && updated_config.scan(begin_marker).length == 1 && updated_config.scan(end_marker).length == 1
    abort "Generated block replacement failed"
  end
end

# Resolve, parse, checksum and validate every requested output before changing either file.
atomic_write(options[:config], updated_config) if options[:config]
atomic_write(options[:rules_output], ruleset) if options[:rules_output]

puts "Converted #{converted.length} rules from #{list_name} (#{options[:profile]}); skipped #{skipped.length}."
unless skipped.empty?
  warn "Skipped rule types:"
  skipped.each { |rule| warn "  #{rule}" }
end

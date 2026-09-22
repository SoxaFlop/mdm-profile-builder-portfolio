#!/usr/bin/env ruby

require "yaml"

schema_path, output_path = ARGV
abort "Usage: GenerateRestrictionCatalogue.rb <com.apple.applicationaccess.yaml> <output.swift>" unless schema_path && output_path

schema = YAML.load_file(schema_path)
payload_keys = schema.fetch("payloadkeys")

ipad_keys = payload_keys.select do |entry|
  support = entry["supportedOS"]
  support.nil? || !support.key?("iOS") || support.dig("iOS", "introduced") != "n/a"
end

boolean_keys = ipad_keys.select { |entry| entry["type"] == "<boolean>" }

case_aliases = {
  "allowAirDrop" => "airDrop",
  "allowAppInstallation" => "appInstallation",
  "allowAccountModification" => "accountModification",
  "allowScreenShot" => "screenCapture",
  "allowCamera" => "camera"
}

extra_search_terms = {
  "allowAirDrop" => ["airdrop", "air drop"],
  "allowAppInstallation" => ["app store", "appstore", "app installation", "install apps"],
  "allowAccountModification" => ["account modification", "account changes", "accounts"],
  "allowScreenShot" => ["screenshot", "screenshots", "screen capture", "screen recording"],
  "allowCamera" => ["camera", "photos"],
  "forceAutomaticDateAndTime" => [
    "date and time",
    "date & time",
    "automatic date and time",
    "change the date and time",
    "changing the date and time",
    "set automatically"
  ]
}

title_overrides = {
  "allowAirDrop" => "AirDrop",
  "allowAppInstallation" => "App installation / App Store",
  "allowAccountModification" => "Account modification",
  "allowScreenShot" => "Screenshots and screen recording",
  "allowCamera" => "Camera",
  "forceAutomaticDateAndTime" => "Automatic date and time"
}

def semantics(key)
  return ".permission" if key.start_with?("allow")
  return ".requirement" if key.start_with?("force", "require")

  ".toggle"
end

def case_name(entry, aliases)
  aliases.fetch(entry.fetch("key"), entry.fetch("key"))
end

def humanise(key)
  value = key
    .gsub(/([a-z0-9])([A-Z])/, '\\1 \\2')
    .gsub(/([A-Za-z])(\d)/, '\\1 \\2')
    .gsub(/(\d)([A-Za-z])/, '\\1 \\2')
  value.sub(/\Aallow /i, "Allow ").sub(/\Aforce /i, "Require ")
end

def swift_string(value)
  escaped = value.to_s
    .encode("UTF-8", invalid: :replace, undef: :replace)
    .gsub("\\", "\\\\")
    .gsub('"', '\\"')
    .gsub("\n", "\\n")
    .gsub("\r", "")
  "\"#{escaped}\""
end

def summary(entry)
  value = entry["content"].to_s.gsub(/\s+/, " ").strip
  value = "Apple device-management restriction." if value.empty?
  value.length > 300 ? "#{value[0, 297]}..." : value
end

def minimum_os(entry)
  introduced = entry.dig("supportedOS", "iOS", "introduced")
  introduced = "4.0" if introduced.nil? || introduced.empty?
  "iPadOS #{introduced}"
end

def supervision(entry)
  entry.dig("supportedOS", "iOS", "supervised") == true ? ".required" : ".notRequired"
end

enum_cases = boolean_keys.map do |entry|
  name = case_name(entry, case_aliases)
  raw_value = entry.fetch("key")
  "    case #{name} = #{swift_string(raw_value)}"
end.join("\n")

definitions = boolean_keys.map do |entry|
  key = entry.fetch("key")
  title = title_overrides.fetch(key, entry["title"] || humanise(key))
  search_terms = ([title.downcase, humanise(key).downcase, key.downcase] + extra_search_terms.fetch(key, [])).uniq
  <<~SWIFT.chomp
        RestrictionDefinition(
            key: .#{case_name(entry, case_aliases)},
            title: #{swift_string(title)},
            summary: #{swift_string(summary(entry))},
            minimumOS: #{swift_string(minimum_os(entry))},
            supervision: #{supervision(entry)},
            searchTerms: [#{search_terms.map { |term| swift_string(term) }.join(", ")}],
            semantics: #{semantics(key)}
        )
  SWIFT
end.join(",\n")

source = <<~SWIFT
  // Generated from Apple's com.apple.applicationaccess device-management schema.
  // Source: https://github.com/apple/device-management
  // Schema snapshot: iOS/iPadOS 26.4. Regenerate with Tools/GenerateRestrictionCatalogue.rb.

  import Foundation

  enum SupervisionRequirement: String {
      case required = "Required"
      case recommended = "Recommended"
      case notRequired = "Not required"
  }

  enum RestrictionValueType: String {
      case boolean
  }

  enum BooleanRestrictionSemantics: String {
      case permission
      case requirement
      case toggle
  }

  enum RestrictionKey: String, Codable, CaseIterable, Identifiable {
  #{enum_cases}

      var id: String { rawValue }
  }

  struct RestrictionDefinition: Identifiable, Equatable {
      let key: RestrictionKey
      let title: String
      let summary: String
      let minimumOS: String
      let supervision: SupervisionRequirement
      let searchTerms: [String]
      let semantics: BooleanRestrictionSemantics
      let valueType: RestrictionValueType = .boolean

      var id: RestrictionKey { key }

      func label(for state: RestrictionState) -> String {
          switch (semantics, state) {
          case (_, .unchanged): "Unchanged"
          case (.permission, .allow): "Allow"
          case (.permission, .deny): "Disable"
          case (.requirement, .allow): "Require"
          case (.requirement, .deny): "Do not require"
          case (.toggle, .allow): "Enable"
          case (.toggle, .deny): "Disable"
          }
      }
  }

  enum RestrictionCatalogue {
      static let schemaVersion = "Apple iOS/iPadOS 26.4"

      static let iPadOS: [RestrictionDefinition] = [
  #{definitions}
      ]

      static func definition(for key: RestrictionKey) -> RestrictionDefinition {
          iPadOS.first(where: { $0.key == key })!
      }

      static func resolve(_ value: String) -> RestrictionKey? {
          let cleaned = value.trimmingCharacters(in: .whitespacesAndNewlines)
          if let exactKey = RestrictionKey(rawValue: cleaned) { return exactKey }
          let normalised = cleaned.lowercased()
          let matches = iPadOS.filter { definition in
              definition.title.lowercased() == normalised ||
                  definition.searchTerms.contains(normalised)
          }
          return matches.count == 1 ? matches[0].key : nil
      }

      static func relevant(to prompt: String, limit: Int = 20) -> [RestrictionDefinition] {
          let query = prompt.lowercased()
          let matches = iPadOS.filter { definition in
              definition.searchTerms.contains(where: query.contains)
          }
          return Array(matches.prefix(limit))
      }
  }
SWIFT

File.write(output_path, source)
puts "Generated #{boolean_keys.count} iPadOS boolean restrictions in #{output_path}"

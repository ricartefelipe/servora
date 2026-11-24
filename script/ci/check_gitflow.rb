# frozen_string_literal: true

# Validates a pull request against the GitFlow rules in CONTRIBUTING.md:
#   feature/<descricao>  -> develop
#   release/<x.y.z>      -> main (and back into develop)
#   hotfix/<x.y.z>       -> main (and back into develop or the active release)
#   dependabot/<...>     -> develop
# and checks that every non-merge commit follows Conventional Commits.
require "open3"

HEAD_REF = ENV.fetch("HEAD_REF")
BASE_REF = ENV.fetch("BASE_REF")
BASE_SHA = ENV.fetch("BASE_SHA")
HEAD_SHA = ENV.fetch("HEAD_SHA")

SEMVER = /\d+\.\d+\.\d+/
RULES = [
  { pattern: %r{\Afeature/[a-z0-9]+(?:-[a-z0-9]+)*\z}, bases: [/\Adevelop\z/] },
  { pattern: %r{\Arelease/#{SEMVER}\z}, bases: [/\Amain\z/, /\Adevelop\z/] },
  { pattern: %r{\Ahotfix/#{SEMVER}\z}, bases: [/\Amain\z/, /\Adevelop\z/, %r{\Arelease/#{SEMVER}\z}] },
  { pattern: %r{\Adependabot/}, bases: [/\Adevelop\z/] }
].freeze

CONVENTIONAL = %r{\A(feat|fix|docs|style|refactor|perf|test|build|ci|chore|revert)(\([a-z0-9\-/]+\))?!?: \S.{0,99}\z}

errors = []

rule = RULES.find { |candidate| candidate[:pattern].match?(HEAD_REF) }
if rule.nil?
  errors << "Branch '#{HEAD_REF}' não segue feature/<descricao>, release/<x.y.z> ou hotfix/<x.y.z>."
elsif rule[:bases].none? { |base| base.match?(BASE_REF) }
  errors << "Branch '#{HEAD_REF}' não pode ser integrada em '#{BASE_REF}'."
end

log, status = Open3.capture2("git", "log", "--no-merges", "--format=%H%x09%s", "#{BASE_SHA}..#{HEAD_SHA}")
abort "Não foi possível ler os commits do pull request." unless status.success?

log.each_line(chomp: true) do |line|
  sha, subject = line.split("\t", 2)
  errors << "Commit #{sha[0, 8]} fora do padrão Conventional Commits: #{subject.inspect}" unless CONVENTIONAL.match?(subject.to_s)
end

if errors.any?
  warn errors.join("\n")
  exit 1
end

puts "Fluxo validado: #{HEAD_REF} -> #{BASE_REF}, #{log.lines.size} commit(s) conforme o padrão."

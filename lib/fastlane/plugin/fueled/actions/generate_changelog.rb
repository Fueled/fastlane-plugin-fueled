require_relative '../helper/fueled_helper'

class String
  def underscore
    self.gsub(/::/, '/').
      gsub(/([A-Z]+)([A-Z][a-z])/, '\1_\2').
      gsub(/([a-z\d])([A-Z])/, '\1_\2').
      tr("-", "_").
      downcase
  end

  def to_titlecase
    return self.underscore.split(/[ _]/).map(&:capitalize).join(' ')
  end
end

module Fastlane
  module Actions
    module SharedValues
      CHANGELOG_GITHUB = :CHANGELOG_GITHUB
      CHANGELOG_SLACK_DEV = :CHANGELOG_SLACK_DEV
      CHANGELOG_SLACK_PUBLIC = :CHANGELOG_SLACK_PUBLIC
      CHANGELOG_PLAINTEXT_PUBLIC = :CHANGELOG_PLAINTEXT_PUBLIC
      CHANGELOG_MARKDOWN_PUBLIC = :CHANGELOG_MARKDOWN_PUBLIC
    end

    class GenerateChangelogAction < Action
      def self.git_retrieve_commits(revision1, revision2)
        git_format = $git_format_info.map { |info| $git_format_selectors[info] }.join("\t")

        if FastlaneCore::Helper.linux?
          return `git log --no-merges "#{revision1}"..#{revision2} --format=\"#{git_format}\" | tac`
        else
          return `git log --no-merges "#{revision1}"..#{revision2} --format=\"#{git_format}\" | tail -r`
        end
      end

      def self.run(params)
        last_config_tag = other_action.last_git_tag(pattern: "v*-#{params[:build_config]}*#{params[:suffix]}*") || ""
        if last_config_tag.empty?
          first_commit = sh("git rev-list --max-parents=0 HEAD | xargs echo -n")
          logs = git_retrieve_commits(first_commit, "HEAD")
        else
          logs = git_retrieve_commits(last_config_tag, "HEAD")
        end
        changelog_github = format_logs(logs, :github, true, params[:ticket_base_url])
        changelog_slack_dev = format_logs(logs, :slack, true, params[:ticket_base_url])
        changelog_slack_public = format_logs(logs, :slack, false, params[:ticket_base_url])
        changelog_plaintext_public = format_logs(logs, :plaintext, false, params[:ticket_base_url])
        changelog_markdown_public = format_logs(logs, :markdown, false, params[:ticket_base_url])
        Actions.lane_context[SharedValues::CHANGELOG_GITHUB] = changelog_github
        Actions.lane_context[SharedValues::CHANGELOG_SLACK_DEV] = changelog_slack_dev
        Actions.lane_context[SharedValues::CHANGELOG_SLACK_PUBLIC] = changelog_slack_public
        Actions.lane_context[SharedValues::CHANGELOG_PLAINTEXT_PUBLIC] = changelog_plaintext_public
        Actions.lane_context[SharedValues::CHANGELOG_MARKDOWN_PUBLIC] = changelog_markdown_public
      end

      #####################################################
      # @!group Documentation
      #####################################################

      def self.description
        "Generate a changelog"
      end

      def self.details
        "Changelog is made of commits between now, and the previous tag using the same build configuration"
      end

      def self.available_options
        [
          FastlaneCore::ConfigItem.new(
            key: :build_config,
            env_name: "BUILD_CONFIGURATION",
            description: "The build configuration (eg: Debug)",
            optional: true,
            default_value: "Debug"
          ),
          FastlaneCore::ConfigItem.new(
            key: :ticket_base_url,
            env_name: "TICKET_BASE_URL",
            description: "The base url of the tickets for eg. https://linear.app/fueled/issue/",
            optional: true,
            default_value: "https://linear.app/fueled/issue/"
          ),
          FastlaneCore::ConfigItem.new(
            key: :suffix,
            env_name: "SUFFIX",
            description: "The suffix used to distinguish platforms with shared codebase (eg: -iOS, -macOS)",
            optional: false,
            default_value: ""
          )
        ]
      end

      def self.output
        [
          ['CHANGELOG_GITHUB', 'Github Ready Changelog'],
          ['CHANGELOG_SLACK_DEV', 'Slack Ready Changelog'],
          ['CHANGELOG_SLACK_PUBLIC', 'Slack Ready Changelog'],
          ['CHANGELOG_PLAINTEXT_PUBLIC', 'Plaintext Ready Changelog'],
          ['CHANGELOG_MARKDOWN_PUBLIC', 'Markdown Ready Changelog']
        ]
      end

      def self.authors
        ["fueled"]
      end

      def self.is_supported?(platform)
        true
      end

      $git_format_selectors = {
        'message' => '%s',
        'author' => '%an',
        'email' => '%ae',
        'hash' => '%H',
        'short_hash' => '%h'
      }

      $git_format_info = $git_format_selectors.map { |key, value| key }

      def self.is_ticket_assigned(scope)
        return scope.include?('-') && scope.split('-').count == 2 && !!/\A\d+\z/.match(scope.split('-').last)
      end

      def self.format_scope(scope, formatting_type, ticket_base_url)
        scopes = scope.split(',')
        if scopes.count > 1
          return scopes.map { |s| format_scope(s, formatting_type, ticket_base_url) }.join(', ')
        end

        scope.strip!
        if is_ticket_assigned(scope)
          formatted_scope = scope.upcase
          case formatting_type
          when :github, :markdown
            "[#{formatted_scope}](#{ticket_base_url}#{formatted_scope})"
          when :slack
            "<#{ticket_base_url}#{formatted_scope}|#{formatted_scope}>"
          when :plaintext
            formatted_scope
          end
        else
          scope.to_titlecase
        end
      end

      def self.format_logs(logs, formatting_type, dev = false, ticket_base_url)
        return nil unless logs && !logs.empty?

        other_type = 'other'
        type_keywords = {
          'feat' => {
            name: 'New Features'
          },
          'fix' => {
            name: 'Bug Fixes'
          },
          'perf' => {
            name: 'Performance Enhancements'
          },
          'refactor' => {
            name: 'Refactorings',
            dev: true
          },
          'docs' => {
            name: 'Documentation Changes',
            dev: true
          },
          'test' => {
            name: 'Test Changes',
            dev: true
          },
          'style' => {
            name: 'Style Changes',
            dev: true
          },
          'chore' => {
            name: 'Configuration Updates',
            dev: true
          },
          other_type => {
            name: 'Other Changes',
            dev: true
          }
        }
        type_keywords_index_helper = type_keywords.map { |key, value| key }

        categorized_line_info = {}
        logs.each_line do |line|
          line_info = {}
          line = line.strip.split("\t")
          $git_format_info.each_with_index do |value, index|
            line_info[value] = line[index]
          end

          message_format_regex = /([^(:]+)(?:\(([^)]*)\))?[[:space:]]*:?[[:space:]]*(.*)/
          match_data = line_info['message'].match(message_format_regex)
          if match_data
            if match_data[3].empty?
              type_keywords.each do |key, value|
                if line_info['message'].downcase.include?(key)
                  line_info['type'] = key
                  break
                end
              end
            else
              base_message = (match_data[3][0, 1].upcase + match_data[3][1..-1]).chomp(".")
              line_info['type'] = match_data[1]
              scope_info = match_data[2].nil? ? [] : match_data[2].split('/')
              if is_ticket_assigned(scope_info.first || '')
                line_info['scope'] = scope_info.first
                line_info['message'] = base_message
              else
                scope_info.map! { |s| format_scope(s, formatting_type, ticket_base_url) }
                if scope_info.count <= 1
                  line_info['scope'] = scope_info.first
                  line_info['message'] = base_message
                else
                  line_info['scope'] = scope_info.first
                  line_info['message'] = "#{scope_info[1..-1].join(' > ')}: #{base_message}"
                end
              end
              if line_info['scope'].nil? || /^[_\-*]*$/ === line_info['scope']
                line_info['scope'] = ''
              end
            end
          end

          next if line_info['message'].downcase.include?('bump') && line_info['message'].downcase.include?('version')

          line_info['type'] = (line_info['type'] || '').downcase

          unless type_keywords[line_info['type']]
            line_info['type'] = other_type
          end

          categorized_line_info[line_info['type']] ||= {}
          categorized_line_info[line_info['type']][line_info['scope']] ||= []
          categorized_line_info[line_info['type']][line_info['scope']] << line_info
        end

        categorized_line_info = categorized_line_info.sort_by { |key, value| type_keywords_index_helper.index(key) || type_keywords_index_helper.index(other_type) }

        changelog_lines = []
        categorized_line_info.each do |type, categorized_scopes|
          next if type_keywords[type][:dev] && !dev

          case formatting_type
          when :github, :markdown
            changelog_lines << "#### #{type_keywords[type][:name]}"
          when :slack
            changelog_lines << "*#{type_keywords[type][:name]}*"
          when :plaintext
            changelog_lines << "> #{type_keywords[type][:name]}"
          end
          categorized_scopes
            .sort_by(&:to_s)
            .each do |scope, value|
            unless scope.nil? || scope.empty?
              case formatting_type
              when :github, :markdown
                changelog_lines << "##### #{format_scope(scope.dup, formatting_type, ticket_base_url)}"
              when :slack
                changelog_lines << "- _#{format_scope(scope.dup, formatting_type, ticket_base_url)}_"
              when :plaintext
                changelog_lines << "> #{scope}"
              end
            end
            value.each do |line_info|
              author_name = "#{line_info['author']} (#{line_info['email']})"
              bullet_character = [:slack, :plaintext].include?(formatting_type) ? "•" : "-"
              author_string = dev ? "#{author_name}:" : ''
              changelog_lines << "#{bullet_character}#{author_string} #{line_info['message']}"
            end
            changelog_lines << ''
          end
        end

        return changelog_lines.join("\n")
      end
    end
  end
end

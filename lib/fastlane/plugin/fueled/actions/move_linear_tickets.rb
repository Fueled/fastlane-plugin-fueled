require_relative '../helper/fueled_helper'
require 'net/http'
require 'json'
require 'uri'

module Fastlane
  module Actions
    module SharedValues
    end

    class MoveLinearTicketsAction < Action
      def self.run(params)
        if params[:from_state] == nil || 
            params[:to_state] == nil || 
            params[:labels] == nil || 
            params[:linear_api_key] == nil ||
            params[:linear_team_id] == nil
            UI.important("Not updating Linear tickets because of missing parameters.")
            return
        end
        uri = URI("https://api.linear.app/graphql")
        
        get_issues = lambda do |last_cursor|
          labels = params[:labels].split(",")
          query = """
          query {
            team(id: \"#{params[:linear_team_id]}\") {
              issues(
                first: 250,
                #{last_cursor == nil ? "": "after: #{last_cursor},"}
                filter: {state: {id: {eq: \"#{params[:from_state]}\"}}, labels: {id: {in: #{labels}}}}
              ) {
                nodes {
                  id
                  title
                }
                pageInfo {
                  hasNextPage
                  endCursor
                }
              }
            }
          }
          """
          res = Net::HTTP.start(uri.host, uri.port, use_ssl: true) do |http|
            req = Net::HTTP::Post.new(uri)
            req['Content-Type'] = 'application/json'
            req['Authorization'] = "#{params[:linear_api_key]}"
            req.body = JSON[{'query' => query}]
            http.request(req)
          end
          res.body
        end

        update_issue = lambda do |issue_id|
            query = """
              mutation {
                issueUpdate(id: \"#{issue_id}\", input: { stateId: \"#{params[:to_state]}\" }) {
                  success
                }
              }
            """
            res = Net::HTTP.start(uri.host, uri.port, use_ssl: true) do |http|
              req = Net::HTTP::Post.new(uri)
              req['Content-Type'] = 'application/json'
              req['Authorization'] = "#{params[:linear_api_key]}"
              req.body = JSON[{'query' => query}]
              http.request(req)
            end
            res.body
          end

        should_continue = true
        last_cursor = nil
        while should_continue == true do 
          begin
          body = JSON.parse(get_issues.call(last_cursor))
          issues = body["data"]["team"]["issues"]
          nodes = issues["nodes"]
          nodes.each do |issue|
            update_issue.call(issue["id"])
            UI.message("Updated #{issue["title"]}")
          end
          last_cursor = issues["pageInfo"]["endCursor"]
          should_continue = issues["pageInfo"]["hasNextPage"]
        end
      end

      #####################################################
      # @!group Documentation
      #####################################################

      def self.description
        "Moves linear tickets, filtered by a set of label IDs, from a state to another"
      end

      def self.details
        "Automatically moves Linear tickets form a state to another one, for a specific team and a set of labels (comma separated). If any of the parameter is not provided, the action will emit a warning and be skipped."
      end

      def self.available_options
        [
          FastlaneCore::ConfigItem.new(
            key: :linear_api_key,
            env_name: "FUELED_LINEAR_API_KEY",
            description: "The Linear API key",
            optional: true
          ),
          FastlaneCore::ConfigItem.new(
            key: :linear_team_id,
            env_name: "FUELED_LINEAR_TEAM_ID",
            description: "The Linear Team ID",
            optional: true
          ),
          FastlaneCore::ConfigItem.new(
            key: :from_state,
            env_name: "FUELED_LINEAR_FROM_STATE",
            description: "The state ID to issues should be moved from",
            optional: true
          ),
          FastlaneCore::ConfigItem.new(
            key: :to_state,
            env_name: "FUELED_LINEAR_TO_STATE",
            description: "The state ID to issues should be moved to",
            optional: true
          ),
          FastlaneCore::ConfigItem.new(
            key: :labels,
            env_name: "FUELED_LINEAR_LABELS",
            description: "The label IDs of the tickets to filter with (comma separated for multiple)",
            optional: true
          )
        ]
      end

      def self.authors
        ["fueled"]
      end

      def self.is_supported?(platform)
        true
      end
    end
  end
end

# frozen_string_literal: true

require 'xcodeproj'
require 'fastlane_core/ui/ui'

module Fastlane
  module Helper
    module Xcode
      module ProjectParser
        module_function

        # Parse Xcode project or workspace and extract signing info
        #
        # Params:
        # - xcode_path: path to .xcodeproj or .xcworkspace
        #
        # Returns: Hash with path and targets info
        def parse(xcode_path)
          project = if xcode_path.end_with?('.xcworkspace')
                      resolve_project_from_workspace(xcode_path)
                    else
                      Xcodeproj::Project.open(xcode_path)
                    end

          {
            path: xcode_path,
            targets: extract_targets(project)
          }
        end

        # Resolve project from workspace (made public for use in profile_manager)
        def resolve_project_from_workspace(workspace_path)
          ws = Xcodeproj::Workspace.new_from_xcworkspace(workspace_path)

          # Workspace#file_references returns objects with .path
          project_paths = ws.file_references
                            .map(&:path)
                            .select { |path| path.end_with?('.xcodeproj') }

          raise "No .xcodeproj found in workspace #{workspace_path}" if project_paths.empty?

          # Convert relative paths → absolute
          project_paths.map! do |p|
            File.expand_path(File.join(File.dirname(workspace_path), p))
          end

          # Most workspaces have one Xcode project
          # If multiple, pick the first one
          Xcodeproj::Project.open(project_paths.first)
        end

        # Extract signing info from project targets
        def extract_targets(project)
          project.targets.map do |t|
            settings = t.build_configurations.first.build_settings

            {
              name: t.name,
              bundle_id: settings['PRODUCT_BUNDLE_IDENTIFIER'],
              signing_style: settings['CODE_SIGN_STYLE'],
              team_id: settings['DEVELOPMENT_TEAM'],
              profile_specifier: settings['PROVISIONING_PROFILE_SPECIFIER'],
              profile_uuid: settings['PROVISIONING_PROFILE'],
              code_sign_identity: settings['CODE_SIGN_IDENTITY']
            }
          end
        end

        private_class_method :extract_targets
      end
    end
  end
end


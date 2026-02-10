# frozen_string_literal: true

require 'xcodeproj'
require 'fastlane_core/ui/ui'
require_relative 'project_parser'

module Fastlane
  module Helper
    module Xcode
      module ProjectDetector
        module_function

        MAX_DEPTH = 2

        # Detect iOS project type and path (Flutter or native)
        #
        # Params:
        # - base: String, directory to search in (default: current directory)
        #
        # Returns: Hash with type (:flutter, :workspace, :project) and path
        def detect(base = Dir.pwd)
          base = File.expand_path(base)

          # 1) Flutter iOS detection
          flutter_ios = flutter_ios_path(base)
          return { type: :flutter, path: File.join(flutter_ios, 'Runner.xcodeproj') } if flutter_ios

          # 2) Native detection
          result = search_native(base, depth: 0)
          return result if result

          raise "No iOS project found in #{base}"
        end

        # Find Xcode project that contains the given bundle ID
        #
        # Params:
        # - bundle_id: String, bundle identifier to search for
        # - search_path: String, directory to search in (default: current directory)
        #
        # Returns: Hash with project_path and target info, or nil if not found
        def find_project_with_bundle_id(bundle_id:, search_path: Dir.pwd)
          # First try to detect project type
          begin
            detected = detect(search_path)
            project_path = detected[:path]

            # Parse project to check bundle IDs
            parsed = ProjectParser.parse(project_path)
            parsed[:targets].each do |target|
              target_bundle_id = target[:bundle_id]
              
              # Handle variable references
              if target_bundle_id && target_bundle_id.include?('$(')
                # Try to resolve common variables
                # This is a simplified approach - full resolution would need project context
                next
              end

              if target_bundle_id == bundle_id
                return {
                  project_path: project_path,
                  target_name: target[:name],
                  workspace_path: detected[:type] == :workspace ? detected[:path] : nil
                }
              end
            end
          rescue StandardError => e
            UI.important("⚠ Could not detect project: #{e.message}")
          end

          # Fallback: search all projects
          projects = []
          workspaces = []

          Dir.glob(File.join(search_path, '**/*.xcodeproj')).each do |proj|
            projects << proj
          end

          Dir.glob(File.join(search_path, '**/*.xcworkspace')).each do |ws|
            workspaces << ws
          end

          # Check projects first
          projects.each do |project_path|
            result = check_project_for_bundle_id(project_path, bundle_id)
            return result if result
          end

          # Check workspaces
          workspaces.each do |workspace_path|
            result = check_workspace_for_bundle_id(workspace_path, bundle_id)
            return result if result
          end

          nil
        end

        # Flutter iOS detection
        def flutter_ios_path(base)
          ios = File.join(base, 'ios')
          return nil unless Dir.exist?(ios)

          runner = File.join(ios, 'Runner.xcodeproj')
          return ios if Dir.exist?(runner)

          nil
        end

        # Native project search
        def search_native(dir, depth:)
          return nil if depth > MAX_DEPTH
          return nil unless File.directory?(dir)

          entries = Dir.children(dir).map { |e| File.join(dir, e) }

          ws = entries.find { |p| p.end_with?('.xcworkspace') }
          return { type: :workspace, path: ws } if ws

          proj = entries.find { |p| p.end_with?('.xcodeproj') }
          return { type: :project, path: proj } if proj

          entries.each do |path|
            next unless File.directory?(path)
            next if path.end_with?('.xcworkspace')
            next if path.end_with?('.xcodeproj')

            found = search_native(path, depth: depth + 1)
            return found if found
          end

          nil
        end

        # Check if a project contains the bundle ID
        def check_project_for_bundle_id(project_path, bundle_id)
          return nil unless File.exist?(project_path)

          begin
            project = Xcodeproj::Project.open(project_path)

            project.targets.each do |target|
              target.build_configurations.each do |config|
                config_bundle_id = config.build_settings['PRODUCT_BUNDLE_IDENTIFIER']
                
                # Handle variable references like $(PRODUCT_BUNDLE_IDENTIFIER_BASE).app
                if config_bundle_id && config_bundle_id.include?('$(')
                  # Try to resolve the variable
                  base_id = config.build_settings['PRODUCT_BUNDLE_IDENTIFIER_BASE']
                  if base_id
                    resolved_bundle_id = config_bundle_id.gsub('$(PRODUCT_BUNDLE_IDENTIFIER_BASE)', base_id)
                    config_bundle_id = resolved_bundle_id
                  end
                end

                if config_bundle_id == bundle_id
                  return {
                    project_path: project_path,
                    target_name: target.name,
                    configuration_name: config.name
                  }
                end
              end
            end
          rescue StandardError => e
            UI.important("⚠ Could not read project #{project_path}: #{e.message}")
          end

          nil
        end

        # Check if a workspace contains a project with the bundle ID
        def check_workspace_for_bundle_id(workspace_path, bundle_id)
          return nil unless File.exist?(workspace_path)

          # Read workspace to find referenced projects
          workspace_data_path = File.join(workspace_path, 'contents.xcworkspacedata')
          return nil unless File.exist?(workspace_data_path)

          workspace_data = File.read(workspace_data_path)
          project_refs = workspace_data.scan(/location = "([^"]+\.xcodeproj)"/)

          project_refs.each do |project_ref|
            project_name = project_ref.first
            workspace_dir = File.dirname(workspace_path)
            project_path = File.expand_path(project_name, workspace_dir)

            result = check_project_for_bundle_id(project_path, bundle_id)
            if result
              result[:workspace_path] = workspace_path
              return result
            end
          end

          nil
        end

        private_class_method :check_project_for_bundle_id, :check_workspace_for_bundle_id
      end
    end
  end
end


require_relative '../helper/fueled_helper'
require_relative '../library/apple_dev_portal/profiles/profile_manager'
require_relative '../library/xcode/project_updater'

module Fastlane
  module Actions
    module SharedValues
      PROVISIONING_PROFILE_INFO = :PROVISIONING_PROFILE_INFO
    end

    class EnsureProvisioningProfilesAction < Action
      def self.run(params)
        UI.message("Ensuring provisioning profiles...")

          profile_info = Helper::AppleDevPortal::Profiles::ProfileManager.ensure_profile(
          key_id: params[:key_id],
          issuer_id: params[:issuer_id],
          key_content: params[:key_content],
          key_file_path: params[:key_file_path],
          bundle_id: params[:bundle_id],
          profile_type: params[:profile_type],
          profile_name: params[:profile_name],
          certificate_id: params[:certificate_id],
          app_store_connect_app_id: params[:app_store_connect_app_id],
          project_path: params[:project_path],
          search_path: params[:search_path]
        )

        if profile_info
          Actions.lane_context[SharedValues::PROVISIONING_PROFILE_INFO] = profile_info
          
          begin
            Helper::Xcode::ProjectUpdater.update_provisioning_profile_from_lane_context
          rescue StandardError => e
            UI.important("⚠ Could not update Xcode project: #{e.message}")
            UI.important("   You may need to call Helper::Xcode::ProjectUpdater.update_provisioning_profile_from_lane_context after build tools run")
          end
          
          UI.success("✓ Provisioning profile ensured successfully!")
          profile_info
        else
          UI.user_error!("Failed to ensure provisioning profile")
        end
      end

      #####################################################
      # @!group Documentation
      #####################################################

      def self.description
        "Ensure iOS provisioning profiles exist on App Store Connect and are installed locally"
      end

      def self.details
        "This action checks if a provisioning profile exists on App Store Connect for the given bundle ID and profile type. " \
        "If not found, it creates a new profile and installs it to ~/Library/MobileDevice/Provisioning Profiles/. " \
        "Supports multiple App Store Connect apps with the same bundle ID via app_store_connect_app_id parameter. " \
        "Credentials can be provided via environment variables or parameters."
      end

      def self.available_options
        [
          FastlaneCore::ConfigItem.new(
            key: :bundle_id,
            env_name: "BUNDLE_ID",
            description: "Bundle identifier (e.g., com.example.app)",
            is_string: true,
            optional: false
          ),
          FastlaneCore::ConfigItem.new(
            key: :profile_type,
            env_name: "PROVISIONING_PROFILE_TYPE",
            description: "Profile type (IOS_APP_STORE, IOS_APP_ADHOC, IOS_APP_DEVELOPMENT)",
            is_string: true,
            optional: true,
            default_value: "IOS_APP_STORE",
            verify_block: proc do |value|
              valid_types = %w[IOS_APP_STORE IOS_APP_ADHOC IOS_APP_DEVELOPMENT]
              unless valid_types.include?(value)
                UI.user_error!("Invalid profile_type: #{value}. Must be one of: #{valid_types.join(', ')}")
              end
            end
          ),
          FastlaneCore::ConfigItem.new(
            key: :profile_name,
            env_name: "PROVISIONING_PROFILE_NAME",
            description: "Name for the provisioning profile (auto-generated if not provided)",
            is_string: true,
            optional: true
          ),
          FastlaneCore::ConfigItem.new(
            key: :certificate_id,
            env_name: "CERTIFICATE_ID",
            description: "Certificate ID to use (uses distribution certificate if not provided)",
            is_string: true,
            optional: true
          ),
          FastlaneCore::ConfigItem.new(
            key: :app_store_connect_app_id,
            env_name: "APP_STORE_CONNECT_APP_ID",
            description: "App Store Connect app ID (for multiple apps with same bundle ID)",
            is_string: true,
            optional: true
          ),
          FastlaneCore::ConfigItem.new(
            key: :key_id,
            env_name: "APP_STORE_CONNECT_KEY_ID",
            description: "App Store Connect Key ID (10-character string)",
            is_string: true,
            optional: true
          ),
          FastlaneCore::ConfigItem.new(
            key: :issuer_id,
            env_name: "APP_STORE_CONNECT_ISSUER_ID",
            description: "App Store Connect Issuer ID (UUID)",
            is_string: true,
            optional: true
          ),
          FastlaneCore::ConfigItem.new(
            key: :key_content,
            env_name: "APP_STORE_CONNECT_KEY_CONTENT",
            description: "App Store Connect private key content (p8 file content as string)",
            is_string: true,
            optional: true
          ),
          FastlaneCore::ConfigItem.new(
            key: :key_file_path,
            env_name: "APP_STORE_CONNECT_KEY_FILE",
            description: "Path to App Store Connect private key file (.p8)",
            is_string: true,
            optional: true
          ),
          FastlaneCore::ConfigItem.new(
            key: :project_path,
            env_name: "PROJECT_PATH",
            description: "Path to Xcode project (.xcodeproj) or workspace (.xcworkspace) (auto-detected from bundle_id if not provided)",
            is_string: true,
            optional: true
          ),
          FastlaneCore::ConfigItem.new(
            key: :search_path,
            env_name: "SEARCH_PATH",
            description: "Directory to search for Xcode projects when auto-detecting (default: current directory)",
            is_string: true,
            optional: true,
            default_value: Dir.pwd
          )
        ]
      end

      def self.output
        [
          ['PROVISIONING_PROFILE_INFO', 'Hash containing profile information (id, name, uuid, type)']
        ]
      end

      def self.authors
        ["fueled"]
      end

      def self.is_supported?(platform)
        [:ios, :mac].include?(platform)
      end

      def self.example_code
        [
          '# Ensure App Store profile using environment variables',
          'ensure_provisioning_profiles(',
          '  bundle_id: "com.example.app",',
          '  profile_type: "IOS_APP_STORE"',
          ')',
          '',
          '# Ensure Ad Hoc profile with explicit credentials',
          'ensure_provisioning_profiles(',
          '  bundle_id: "com.example.app",',
          '  profile_type: "IOS_APP_ADHOC",',
          '  profile_name: "My App Ad Hoc",',
          '  key_id: "ABC123DEFG",',
          '  issuer_id: "12345678-1234-1234-1234-123456789012",',
          '  key_file_path: "path/to/AuthKey.p8"',
          ')',
          '',
          '# Ensure profile for specific App Store Connect app (multiple apps with same bundle ID)',
          'ensure_provisioning_profiles(',
          '  bundle_id: "com.example.app",',
          '  profile_type: "IOS_APP_STORE",',
          '  app_store_connect_app_id: "1234567890"',
          ')'
        ]
      end

      def self.category
        :code_signing
      end
    end
  end
end


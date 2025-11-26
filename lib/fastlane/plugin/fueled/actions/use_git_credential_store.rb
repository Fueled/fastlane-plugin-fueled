module Fastlane
  module Actions
    class UseGitCredentialStoreAction < Action
      def self.run(params)
        repo_root = sh("git rev-parse --show-toplevel").strip
        path = File.join(repo_root, ".git/git-credentials")

        credentials = <<~CREDS
          protocol=https
          host=#{params[:git_host]}
          username=#{params[:git_user_name]}
          password=#{params[:git_token]}
        CREDS

        # Write credentials file
        File.write(path, credentials)

        # Configure Git repo to use this file
        sh(%Q{git config credential.helper "store --file=#{path}"})

        UI.success("Git credentials stored locally in .git/git-credentials ✅")
      rescue => e
        UI.user_error!("Failed to store credentials: #{e}")
      end

      #####################################################
      # @!group Documentation
      #####################################################

      def self.description
        "Employ Git's credential storage to securely save the Git username and password/token, eliminating the need to specify them repeatedly with each Git command."
      end

      def self.available_options
        [
          FastlaneCore::ConfigItem.new(
            key: :git_token,
            env_name: "GIT_TOKEN",
            description: "The git token that will be added to the git credential store",
            is_string: true,
            optional: false
          ),
          FastlaneCore::ConfigItem.new(
            key: :git_user_name,
            env_name: "GIT_USER_NAME",
            description: "The git username that will be added to the git credential store",
            is_string: true,
            optional: true,
            default_value: "Fueled"
          ),
          FastlaneCore::ConfigItem.new(
            key: :git_host,
            env_name: "GIT_HOST",
            description: "The host of your git repository (e.g. github.com, bitbucket.com, or gitlab.com)",
            is_string: true,
            optional: true,
            default_value: "github.com"
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

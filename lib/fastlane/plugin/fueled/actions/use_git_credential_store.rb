module Fastlane
    module Actions

        class UseGitCredentialStoreAction < Action
        
            def self.run(params)
                commands = <<~BASH
                git config --global credential.helper store

                git credential-store --file ~/.git-credentials store << EOF
                protocol=https
                host=#{params[:git_host]}
                username=#{params[:git_user_name]}
                password=#{params[:git_token]}
              BASH
              
              if system(commands)
                UI.success("Your git credentials are saved to the git credential store ✅.")
              else
                UI.user_error!("Something went wrong, your git credentials are not saved. 🚫")
              end
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
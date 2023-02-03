module Fastlane
    module Actions
      module SharedValues
      end
  
      class GenerateSecretsIosAction < Action
        def self.run(params)
          template_file = params[:template_file]
          environment_file = params[:environment_file]
          UI.message("Generating ArkanaKeys Package")
          sh("bundle exec arkana -c #{template_file} -e #{environment_file}")
        end
  
        #####################################################
        # @!group Documentation
        #####################################################
  
        def self.description
          "Generate ArkanaKeys Package with project secrets"
        end
  
        def self.available_options
          [
            FastlaneCore::ConfigItem.new(
              key: :template_file,
              env_name: "ARKANA_TEMPLATE_FILE",
              description: "The template file used to generate the Arkana Keys Package",
              is_string: true,
              default_value: ".arkana.yml"
            ),
            FastlaneCore::ConfigItem.new(
              key: :environment_file,
              env_name: "ARKANA_ENVIRONMENT_FILE",
              description: "The environment file containing the secrets",
              is_string: true,
              default_value: ".env.arkana_ci"
            )
          ]
        end
  
        def self.authors
          ["fueled"]
        end
  
        def self.is_supported?(platform)
            [:ios, :mac].include?(platform)
        end
      end
    end
  end
  
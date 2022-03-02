module Fastlane
  module Actions
    module SharedValues
    end

    class FormattingChecksFlutterAction < Action
      def self.run(params)
        UI.message("Checking formatting")
        sh("flutter pub get")
        sh("flutter format -o none --set-exit-if-changed .")
      end

      #####################################################
      # @!group Documentation
      #####################################################

      def self.description
        "Check formatting for a Flutter project"
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

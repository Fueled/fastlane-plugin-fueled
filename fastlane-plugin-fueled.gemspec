lib = File.expand_path("lib", __dir__)
$LOAD_PATH.unshift(lib) unless $LOAD_PATH.include?(lib)
require 'fastlane/plugin/fueled/version'

Gem::Specification.new do |spec|
  spec.name          = 'fastlane-plugin-fueled'
  spec.version       = Fastlane::Fueled::VERSION
  spec.author        = 'Benoit Layer'
  spec.email         = '1849419+notbenoit@users.noreply.github.com'

  spec.summary       = 'Fueled fastlane plugin'
  spec.homepage      = "https://github.com/Fueled/fastlane-plugin-fueled"
  spec.license       = "MIT"

  spec.files         = Dir["lib/**/*"] + %w(README.md LICENSE)
  spec.test_files    = spec.files.grep(%r{^(test|spec|features)/})
  spec.require_paths = ['lib']

  spec.required_ruby_version = '>= 2.5'

  spec.add_dependency('fastlane-plugin-appcenter', '~> 2.0.0')
  spec.add_dependency('fastlane-plugin-versioning', '~> 0.5.0')
  spec.add_dependency('concurrent-ruby')
  spec.add_development_dependency('bundler')
  spec.add_development_dependency('fastlane', '>= 2.197.0')
  spec.add_development_dependency('pry')
  spec.add_development_dependency('rake')
  spec.add_development_dependency('rspec')
  spec.add_development_dependency('rspec_junit_formatter')
  spec.add_development_dependency('rubocop', '1.12.1')
  spec.add_development_dependency('rubocop-performance')
  spec.add_development_dependency('rubocop-require_tools')
  spec.add_development_dependency('simplecov')
end

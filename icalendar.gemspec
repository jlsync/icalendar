require File.join File.dirname(__FILE__), 'lib', 'icalendar', 'version'

Gem::Specification.new do |s|
  s.authors = ['Ryan Ahearn']
  s.email   = ['ryan.c.ahearn@gmail.com']

  s.name = "icalendar"
  s.version = Icalendar::VERSION
  s.licenses = ['BSD-2-Clause', 'GPL-3.0-only', 'icalendar']

  s.homepage = "https://github.com/icalendar/icalendar"
  s.platform = Gem::Platform::RUBY
  s.summary = "A Ruby implementation of the iCalendar specification (RFC 5545)."
  s.description = <<-EOD
Implements the iCalendar specification (RFC 5545) in Ruby.  This allows
for the generation and parsing of .ics files, which are used by a
variety of calendaring applications.
  EOD
  s.post_install_message = <<-EOM
ActiveSupport is required for TimeWithZone support, but not required for general use.
  EOM

  s.metadata = {
    'changelog_uri' => 'https://github.com/icalendar/icalendar/blob/main/CHANGELOG.md'
  }

  s.files = `git ls-files`.split "\n"
  s.test_files = `git ls-files -- {test,spec,features}/*`.split "\n"
  s.executables = `git ls-files -- bin/*`.split("\n").map { |f| File.basename f }
  s.require_paths = ['lib']

  s.required_ruby_version = '>= 3.4.0'

  s.add_dependency 'base64'
  s.add_dependency 'ice_cube', '~> 0.16'
  s.add_dependency 'logger'

  s.add_development_dependency 'rake', '~> 13.4'
  s.add_development_dependency 'bundler', '~> 4.0'

  s.add_development_dependency 'activesupport', '~> 8.1'
  s.add_development_dependency 'tzinfo', '~> 2.0.6'
  s.add_development_dependency 'tzinfo-data', '~> 1.2026'

  s.add_development_dependency 'timecop', '~> 0.9.11'
  s.add_development_dependency 'rspec', '~> 3.13'
  s.add_development_dependency 'simplecov', '~> 1.3'
  s.add_development_dependency 'byebug', '~> 13.0'
end

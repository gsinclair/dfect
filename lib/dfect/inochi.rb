module Dfect

  ##
  # Official name of this project.
  #
  PROJECT = "Dfect"

  ##
  # Short single-line description of this project.
  #
  TAGLINE = "Assertion testing library for Ruby"

  ##
  # Address of this project's official home page.
  #
  WEBSITE = "http://snk.tuxfamily.org/lib/dfect/"

  ##
  # Number of this release of this project.
  #
  VERSION = "2.1.0"

  ##
  # Date of this release of this project.
  #
  RELDATE = "2010-03-31"

  ##
  # Description of this release of this project.
  #
  def self.inspect
    "#{PROJECT} #{VERSION} (#{RELDATE})"
  end

  ##
  # Location of this release of this project.
  #
  INSTDIR = File.expand_path('../../..', __FILE__)

  ##
  # RubyGems required by this project during runtime.
  #
  # @example
  #
  #   RUNTIME = {
  #     # this project needs exactly version 1.2.3 of the "an_example" gem
  #     "an_example" => [ "1.2.3" ],
  #
  #     # this project needs at least version 1.2 (but not
  #     # version 1.2.4 or newer) of the "another_example" gem
  #     "another_example" => [ ">= 1.2" , "< 1.2.4" ],
  #
  #     # this project needs any version of the "yet_another_example" gem
  #     "yet_another_example" => [],
  #   }
  #
  RUNTIME = {}

  ##
  # RubyGems required by this project during development.
  #
  # @example
  #
  #   DEVTIME = {
  #     # this project needs exactly version 1.2.3 of the "an_example" gem
  #     "an_example" => [ "1.2.3" ],
  #
  #     # this project needs at least version 1.2 (but not
  #     # version 1.2.4 or newer) of the "another_example" gem
  #     "another_example" => [ ">= 1.2" , "< 1.2.4" ],
  #
  #     # this project needs any version of the "yet_another_example" gem
  #     "yet_another_example" => [],
  #   }
  #
  DEVTIME = {
    "inochi" => [ "~> 2" ], # for managing this project
  }

  ##
  # Loads the correct version (as defined by the {RUNTIME} or {DEVTIME}
  # constant in this module) of the given gem or the gem that contains
  # the given library.
  #
  def self.require gem_name_or_library
    # prepare the correct version of the gem for loading
    if respond_to? :gem
      gem_name = gem_name_or_library.to_s.sub(%r{/.*$}, '')
      if gem_version = RUNTIME[gem_name] || DEVTIME[gem_name]
        begin
          gem gem_name, *gem_version
        rescue LoadError => error
          warn "#{self.inspect}: #{error}"
        end
      end
    end

    # do the loading
    super
  end

end

require 'dfect/inochi'

require 'yaml'

# gsinclair's added requires; incorporate into inochi?
require 'pp'
require 'rubygems'
require 'ruby-debug'
require 'dev-utils/debug'
require 'term/ansicolor'
class String; include Term::ANSIColor; end
gem 'differ'
require 'differ'

module BoldColor
  class << self
    def format(change)
      (change.change? && as_change(change)) ||
        (change.delete? && as_delete(change)) ||
        (change.insert? && as_insert(change)) ||
        ''
    end

    private
    def as_insert(change)
      change.insert.green.bold
    end

    def as_delete(change)
      change.delete.red.bold
    end

    def as_change(change)
      as_delete(change) << as_insert(change)
    end
  end
end
Differ.format = BoldColor

#
# YAML raises this error when we try to serialize a class:
#
#   TypeError: can't dump anonymous class Class
#
# Work around this by representing a class by its name.
#
class Class # @private
  alias __to_yaml__ to_yaml
  undef to_yaml

  def to_yaml opts = {}
    begin
      __to_yaml__
    rescue TypeError => e
      self.name.to_yaml opts
    end
  end
end

# load interactive debugger
begin
  require 'ruby-debug'
rescue LoadError
  require 'irb'
end

module Dfect
  class << Dfect
    ##
    # Hash of test results, assembled by {Dfect.run}.
    #
    # [:trace]
    #   Hierarchical trace of all tests executed, where each test is
    #   represented by its description, is mapped to an Array of
    #   nested tests, and may contain zero or more assertion failures.
    #
    #   Assertion failures are represented as a Hash:
    #
    #   [:fail]
    #     Description of the assertion failure.
    #
    #   [:code]
    #     Source code surrounding the point of failure.
    #
    #   [:vars]
    #     Local variables visible at the point of failure.
    #
    #   [:call]
    #     Stack trace leading to the point of failure.
    #
    # [:stats]
    #   Hash of counts of major events in test execution:
    #
    #   [:time]
    #     Number of seconds elapsed for test execution.
    #
    #   [:pass]
    #     Number of assertions that held true.
    #
    #   [:fail]
    #     Number of assertions that did not hold true.
    #
    #   [:error]
    #     Number of exceptions that were not rescued.
    #
    attr_reader :report

    ##
    # Hash of choices that affect how Dfect operates.
    #
    # [:debug]
    #   Launch an interactive debugger
    #   during assertion failures so
    #   the user can investigate them.
    #
    #   The default value is $DEBUG.
    #
    # [:quiet]
    #   Do not print the report
    #   after executing all tests.
    #
    #   The default value is false.
    #
    attr_accessor :options

    ##
    # Defines a new test composed of the given
    # description and the given block to execute.
    #
    # This test may contain nested tests.
    #
    # Tests at the outer-most level are automatically
    # insulated from the top-level Ruby environment.
    #
    # @param [Object, Array<Object>] description
    #
    #   A brief title or a series of objects
    #   that describe the test being defined.
    #
    # @example
    #
    #   D "a new array" do
    #     D .< { @array = [] }
    #
    #     D "must be empty" do
    #       T { @array.empty? }
    #     end
    #
    #     D "when populated" do
    #       D .< { @array.push 55 }
    #
    #       D "must not be empty" do
    #         F { @array.empty? }
    #       end
    #     end
    #   end
    #
    def D *description, &block
      create_test @tests.empty?, *description, &block
    end

    ##
    # Defines a new test that is explicitly insulated from the tests
    # that contain it and also from the top-level Ruby environment.
    #
    # This test may contain nested tests.
    #
    # @param description (see Dfect.D)
    #
    # @example
    #
    #   D "a root-level test" do
    #     @outside = 1
    #     T { defined? @outside }
    #     T { @outside == 1 }
    #
    #     D "an inner, non-insulated test" do
    #       T { defined? @outside }
    #       T { @outside == 1 }
    #     end
    #
    #     D! "an inner, insulated test" do
    #       F { defined? @outside }
    #       F { @outside == 1 }
    #
    #       @inside = 2
    #       T { defined? @inside }
    #       T { @inside == 2 }
    #     end
    #
    #     F { defined? @inside }
    #     F { @inside == 2 }
    #   end
    #
    def D! *description, &block
      create_test true, *description, &block
    end

    ##
    # @overload def <(&block)
    #
    # Registers the given block to be executed
    # before each nested test inside this test.
    #
    # @example
    #
    #   D .< { puts "before each nested test" }
    #
    #   D .< do
    #     puts "before each nested test"
    #   end
    #
    def <(*args, &block)
      if args.empty?
        raise ArgumentError, 'block must be given' unless block
        @suite.before_each << block
      else
        # the < method is being used as a check for inheritance
        super
      end
    end

    ##
    # Registers the given block to be executed
    # after each nested test inside this test.
    #
    # @example
    #
    #   D .> { puts "after each nested test" }
    #
    #   D .> do
    #     puts "after each nested test"
    #   end
    #
    def > &block
      raise ArgumentError, 'block must be given' unless block
      @suite.after_each << block
    end

    ##
    # Registers the given block to be executed
    # before all nested tests inside this test.
    #
    # @example
    #
    #   D .<< { puts "before all nested tests" }
    #
    #   D .<< do
    #     puts "before all nested tests"
    #   end
    #
    def << &block
      raise ArgumentError, 'block must be given' unless block
      @suite.before_all << block
    end

    ##
    # Registers the given block to be executed
    # after all nested tests inside this test.
    #
    # @example
    #
    #   D .>> { puts "after all nested tests" }
    #
    #   D .>> do
    #     puts "after all nested tests"
    #   end
    #
    def >> &block
      raise ArgumentError, 'block must be given' unless block
      @suite.after_all << block
    end

    ##
    # Asserts that the given condition or the
    # result of the given block is neither
    # nil nor false and returns that result.
    #
    # @param condition
    #
    #   The condition to be asserted.  A block
    #   may be given in place of this parameter.
    #
    # @param message
    #
    #   Optional message to show in the
    #   report if this assertion fails.
    #
    # @example no message given
    #
    #   T { true }  # passes
    #   T { false } # fails
    #   T { nil }   # fails
    #
    # @example message is given
    #
    #   T("computers do not doublethink") { 2 + 2 != 5 } # passes
    #
    def T condition = nil, message = nil, &block
      assert_yield :assert, condition, message, &block
    end

    def Eq actual, expected, message = nil
      assert_equal :assert, actual, expected, message
    end

    def Eq! actual, expected, message = nil
      assert_equal :negate, actual, expected, essage
    end

    def Eq? actual, expected, message = nil
      assert_equal :sample, actual, expected, message
    end

    def N condition = nil, message = nil, &block
      assert_nil :assert, condition, message, &block
    end

    def N! condition = nil, message = nil, &block
      assert_nil :negate, condition, message, &block
    end

    def N? condition = nil, message = nil, &block
      assert_nil :sample, condition, message, &block
    end

    def Mt string, regex, message=nil
      assert_match :assert, string, regex, message
    end

    def Mt! string, regex, message=nil
      assert_match :negate, string, regex, message
    end

    def Mt? string, regex, message=nil
      assert_match :sample, string, regex, message
    end


    ##
    # Asserts that the given condition or the
    # result of the given block is either nil
    # or false and returns that result.
    #
    # @param condition (see Dfect.T)
    #
    # @param message (see Dfect.T)
    #
    # @example no message given
    #
    #   T! { true }  # fails
    #   T! { false } # passes
    #   T! { nil }   # passes
    #
    # @example message is given
    #
    #   T!("computers do not doublethink") { 2 + 2 == 5 } # passes
    #
    def T! condition = nil, message = nil, &block
      assert_yield :negate, condition, message, &block
    end

    ##
    # Returns true if the given condition or
    # the result of the given block is neither
    # nil nor false.  Otherwise, returns false.
    #
    # @param condition (see Dfect.T)
    #
    # @param message
    #
    #   This parameter is optional and completely ignored.
    #
    # @example no message given
    #
    #   T? { true }  # => true
    #   T? { false } # => false
    #   T? { nil }   # => false
    #
    # @example message is given
    #
    #   T?("computers do not doublethink") { 2 + 2 != 5 } # => true
    #
    def T? condition = nil, message = nil, &block
      assert_yield :sample, condition, message, &block
    end

    alias F T!

    alias F! T

    ##
    # Returns true if the result of the given block is
    # either nil or false.  Otherwise, returns false.
    #
    # @param message (see Dfect.T?)
    #
    # @example no message given
    #
    #   F? { true }  # => false
    #   F? { false } # => true
    #   F? { nil }   # => true
    #
    # @example message is given
    #
    #   F?( "computers do not doublethink" ) { 2 + 2 == 5 } # => true
    #
    def F? message = nil, &block
      not T? message, &block
    end

    ##
    # Asserts that one of the given
    # kinds of exceptions is raised
    # when the given block is executed.
    #
    # @return
    #
    #   If the block raises an exception,
    #   then that exception is returned.
    #
    #   Otherwise, nil is returned.
    #
    # @param [...] kinds_then_message
    #
    #   Exception classes that must be raised by the given block, optionally
    #   followed by a message to show in the report if this assertion fails.
    #
    #   If no exception classes are given, then
    #   StandardError is assumed (similar to
    #   how a plain 'rescue' statement without
    #   any arguments catches StandardError).
    #
    # @example no exceptions given
    #
    #   E { }       # fails
    #   E { raise } # passes
    #
    # @example single exception given
    #
    #   E(ArgumentError) { raise ArgumentError }
    #   E(ArgumentError, "argument must be invalid") { raise ArgumentError }
    #
    # @example multiple exceptions given
    #
    #   E(SyntaxError, NameError) { eval "..." }
    #   E(SyntaxError, NameError, "string must compile") { eval "..." }
    #
    def E *kinds_then_message, &block
      assert_raise :assert, *kinds_then_message, &block
    end

    ##
    # Asserts that one of the given kinds of exceptions
    # is not raised when the given block is executed.
    #
    # @return (see Dfect.E)
    #
    # @param kinds_then_message (see Dfect.E)
    #
    # @example no exceptions given
    #
    #   E! { }       # passes
    #   E! { raise } # fails
    #
    # @example single exception given
    #
    #   E!(ArgumentError) { raise ArgumentError } # fails
    #   E!(ArgumentError, "argument must be invalid") { raise ArgumentError }
    #
    # @example multiple exceptions given
    #
    #   E!(SyntaxError, NameError) { eval "..." }
    #   E!(SyntaxError, NameError, "string must compile") { eval "..." }
    #
    def E! *kinds_then_message, &block
      assert_raise :negate, *kinds_then_message, &block
    end

    ##
    # Returns true if one of the given kinds of
    # exceptions is raised when the given block
    # is executed.  Otherwise, returns false.
    #
    # @param [...] kinds_then_message
    #
    #   Exception classes that must be raised by
    #   the given block, optionally followed by
    #   a message that is completely ignored.
    #
    #   If no exception classes are given, then
    #   StandardError is assumed (similar to
    #   how a plain 'rescue' statement without
    #   any arguments catches StandardError).
    #
    # @example no exceptions given
    #
    #   E? { }       # => false
    #   E? { raise } # => true
    #
    # @example single exception given
    #
    #   E?(ArgumentError) { raise ArgumentError } # => true
    #
    # @example multiple exceptions given
    #
    #   E?(SyntaxError, NameError) { eval "..." } # => true
    #   E!(SyntaxError, NameError, "string must compile") { eval "..." }
    #
    def E? *kinds_then_message, &block
      assert_raise :sample, *kinds_then_message, &block
    end

    ##
    # Asserts that the given symbol is thrown
    # when the given block is executed.
    #
    # @return
    #
    #   If a value is thrown along
    #   with the expected symbol,
    #   then that value is returned.
    #
    #   Otherwise, nil is returned.
    #
    # @param [Symbol] symbol
    #
    #   Symbol that must be thrown by the given block.
    #
    # @param message (see Dfect.T)
    #
    # @example no message given
    #
    #   C(:foo) { throw :foo, 123 } # passes, => 123
    #   C(:foo) { throw :bar, 456 } # fails,  => 456
    #   C(:foo) { }                 # fails,  => nil
    #
    # @example message is given
    #
    #   C(:foo, ":foo must be thrown") { throw :bar, 789 } # fails, => nil
    #
    def C symbol, message = nil, &block
      assert_catch :assert, symbol, message, &block
    end

    ##
    # Asserts that the given symbol is not
    # thrown when the given block is executed.
    #
    # @return nil, always.
    #
    # @param [Symbol] symbol
    #
    #   Symbol that must not be thrown by the given block.
    #
    # @param message (see Dfect.T)
    #
    # @example no message given
    #
    #   C!(:foo) { throw :foo, 123 } # fails,  => nil
    #   C!(:foo) { throw :bar, 456 } # passes, => nil
    #   C!(:foo) { }                 # passes, => nil
    #
    # @example message is given
    #
    #   C!(:foo, ":foo must be thrown") { throw :bar, 789 } # passes, => nil
    #
    def C! symbol, message = nil, &block
      assert_catch :negate, symbol, message, &block
    end

    ##
    # Returns true if the given symbol is thrown when the
    # given block is executed.  Otherwise, returns false.
    #
    # @param symbol (see Dfect.C)
    #
    # @param message (see Dfect.T?)
    #
    # @example no message given
    #
    #   C?(:foo) { throw :foo, 123 } # => true
    #   C?(:foo) { throw :bar, 456 } # => false
    #   C?(:foo) { }                 # => false
    #
    # @example message is given
    #
    #   C?(:foo, ":foo must be thrown") { throw :bar, 789 } # => false
    #
    def C? symbol, message = nil, &block
      assert_catch :sample, symbol, message, &block
    end

    ##
    # Adds the given messages to the report inside
    # the section of the currently running test.
    #
    # You can think of "L" as "to log something".
    #
    # @param messages
    #
    #   Objects to be added to the report.
    #
    # @example single message given
    #
    #   L "establishing connection..."
    #
    # @example multiple messages given
    #
    #   L "beginning calculation...", Math::PI, [1, 2, 3, ['a', 'b', 'c']]
    #
    def L *messages
      @trace.concat messages
    end

    ##
    # Mechanism for sharing code between tests.
    #
    # If a block is given, it is shared under
    # the given identifier.  Otherwise, the
    # code block that was previously shared
    # under the given identifier is injected
    # into the closest insulated Dfect test
    # that contains the call to this method.
    #
    # @param [Symbol, Object] identifier
    #
    #   An object that identifies shared code.  This must be common
    #   knowledge to all parties that want to partake in the sharing.
    #
    # @example
    #
    #   S :knowledge do
    #     #...
    #   end
    #
    #   D "some test" do
    #     S :knowledge
    #   end
    #
    #   D "another test" do
    #     S :knowledge
    #   end
    #
    def S identifier, &block
      if block_given?
        if already_shared = @share[identifier]
          raise ArgumentError, "A code block #{already_shared.inspect} has already been shared under the identifier #{identifier.inspect}."
        end

        @share[identifier] = block

      elsif block = @share[identifier]
        if @tests.empty?
          raise "Cannot inject code block #{block.inspect} shared under identifier #{identifier.inspect} outside of a Dfect test."
        else
          # find the closest insulated parent test; this should always
          # succeed because root-level tests are insulated by default
          test = @tests.reverse.find {|t| t.sandbox }
          test.sandbox.instance_eval(&block)
        end

      else
        raise ArgumentError, "No code block is shared under identifier #{identifier.inspect}."
      end
    end

    ##
    # Shares the given code block under the given
    # identifier and then immediately injects that
    # code block into the closest insulated Dfect
    # test that contains the call to this method.
    #
    # @param identifier (see Dfect.S)
    #
    # @example
    #
    #   D "some test" do
    #     S! :knowledge do
    #       #...
    #     end
    #   end
    #
    #   D "another test" do
    #     S :knowledge
    #   end
    #
    def S! identifier, &block
      raise 'block must be given' unless block_given?
      S identifier, &block
      S identifier
    end

    ##
    # Checks whether any code has been shared under the given identifier.
    #
    def S? identifier
      @share.key? identifier
    end

    ##
    # Executes all tests defined thus far and
    # stores the results in {Dfect.report}.
    #
    # @param [Boolean] continue
    #
    #   If true, results from previous executions will not be cleared.
    #
    def run continue = true
      # clear previous results
      unless continue
        @stats.clear
        @trace.clear
        @tests.clear
      end

      # make new results
      start = Time.now
      catch(:stop_dfect_execution) { execute }
      finish = Time.now
      @stats[:time] = finish - start

      # print new results
      unless @stats.key? :fail or @stats.key? :error
        #
        # show execution trace only if all tests passed.
        # otherwise, we will be repeating already printed
        # failure details and obstructing the developer!
        #

        #display @trace    -- boring...
      end

      ### XXX: In this method I can choose what gets displayed and when!
      ### Run the debugger here to see what values are available to me.

      # display @stats    -- boring...

      # Here we display the results (#pass, #fail, #error, #run) and an overall
      # pass/fail/error.
      npass   = @stats[:pass]  || 0
      nfail   = @stats[:fail]  || 0
      nerror  = @stats[:error] || 0
      overall = (nfail + nerror > 0) ? :FAIL : :PASS
      ntotal  = npass + nfail + nerror
      time    = @stats[:time]

      overall_colour = (if overall == :PASS then :green else :red end)
      npass_colour   = :green
      nfail_colour   = (if nfail  > 0 then :red else :green end)
      nerror_colour  = (if nerror > 0 then :red else :green end)
      time_colour    = :white

      overall_str   = overall.to_s.ljust(10).send(overall_colour).bold
      npass_str     = (sprintf "#pass: %-6d",  npass).send(npass_colour).bold
      nfail_str     = (sprintf "#fail: %-6d",  nfail).send(nfail_colour).bold
      nerror_str    = (sprintf "#error: %-6d", nerror).send(nerror_colour).bold
      time_str      = (sprintf "time: %s",      time).send(time_colour)

      equals = ("=" * 80).send(overall_colour).bold + "\n"
      string = equals.dup
      string << overall_str << npass_str << nfail_str << nerror_str << time_str << "\n"
      string << equals

      puts string
    end

    ##
    # Stops the execution of the {Dfect.run} method or raises
    # an exception if that method is not currently executing.
    #
    def stop
      throw :stop_dfect_execution
    end

    ##
    # Returns the details of the failure that
    # is currently being debugged by the user.
    #
    def info
      @trace.last
    end

    private

    def create_test insulate, *description, &block
      raise ArgumentError, 'block must be given' unless block

      description = description.join(' ')
      sandbox = Object.new if insulate

      @suite.tests << Suite::Test.new(description, block, sandbox)
    end

    ### XXX: My new method for asserting equality, to support Eq etc.
    def assert_equal mode, actual, expected, message
      message ||=
        case mode
        when :assert
          String.new.tap { |str|
            str << "Equality test failed\n".yellow.bold
            str << "  Was: #{actual.inspect}\n".red.bold
            str << "  Exp: #{expected.inspect}".green.bold
            if String === actual and String === expected \
                 and expected.length > 40 and actual.length > 40
              diff = Differ.diff_by_char(actual.inspect, expected.inspect)
              str << NL << "  Dif: #{diff}"
            end
          }
        when :negate
          if expected.inspect.length < 10
            "Inequality test failed: object should not equal #{expected.inspect}.red.bold"
          else
            "Inequality test failed: the two objects were equal.\n" <<
            "  Value: #{expected.inspect.red.bold}"
          end
        end

      passed = lambda { @stats[:pass] += 1 }
      #failed = lambda { @stats[:fail] += 1; _debug nil, message }
      failed = lambda { @stats[:fail] += 1; report_failure nil, message }

      result = (expected == actual)

      case mode
      when :sample then return result
      when :assert then result ? passed.call : failed.call
      when :negate then result ? failed.call : passed.call
      end

      result
    end

    def assert_nil mode, condition = nil, message = nil, &block
      # first parameter is actually the message when block is given
      message = condition if block

      message ||= (
        prefix = block ? 'block must yield' : 'condition must be'
        case mode
        when :assert then "#{prefix} nil"
        when :negate then "#{prefix} not nil"
        end
      )

      passed = lambda { @stats[:pass] += 1 }
      failed = lambda { @stats[:fail] += 1; _debug block, message }

      result = block ? call(block) : condition
      result = result.nil?

      case mode
      when :sample then return result ? true : false
      when :assert then result ? passed.call : failed.call
      when :negate then result ? failed.call : passed.call
      end

      result
    end

    def assert_match mode, string, regexp, message = nil
      raise ArgumentError unless String === string and Regexp === regexp
      message ||= (
        _not_ =
          case mode
          when :assert then " "
          when :negate then " NOT "
          end
        "Match failure: string should#{_not_}match regex\n".yellow.bold <<
        "  String: #{string.inspect.truncate(200).red.bold}\n" <<
        "  Regexp: #{regexp.inspect.green.bold}"
      )

      passed = lambda { @stats[:pass] += 1 }
      failed = lambda { @stats[:fail] += 1; report_failure nil, message }

      result = (string =~ regexp)

      case mode
      when :sample then return result ? true : false
      when :assert then result ? passed.call : failed.call
      when :negate then result ? failed.call : passed.call
      end

      result
    end

    def assert_yield mode, condition = nil, message = nil, &block
      # first parameter is actually the message when block is given
      message = condition if block

      message ||= "Assertion failed".yellow.bold

      passed = lambda { @stats[:pass] += 1 }
      failed = lambda { @stats[:fail] += 1; report_failure block, message }

      result = block ? call(block) : condition

      ### XXX: In this method I can emit results to STDOUT as they happen,
      ### rather than wait until the end.

      case mode
      when :sample then return result ? true : false
      when :assert then result ? passed.call : failed.call
      when :negate then result ? failed.call : passed.call
      end

      result
    end

    def assert_raise mode, *kinds_then_message, &block
      raise ArgumentError, 'block must be given' unless block

      message = kinds_then_message.pop
      kinds = kinds_then_message

      if message.kind_of? Class
        kinds << message
        message = nil
      end

      kinds << StandardError if kinds.empty?

      message ||=
        case mode
        when :assert then "block must raise #{kinds.join ' or '}"
        when :negate then "block must not raise #{kinds.join ' or '}"
        end

      passed = lambda do
        @stats[:pass] += 1
      end

      failed = lambda do |exception|
        @stats[:fail] += 1

        if exception
          # debug the uncaught exception...
          _debug_uncaught_exception block, exception

          # ...in addition to debugging this assertion
          _debug block, [message, {'block raised' => exception}]

        else
          _debug block, message
        end

        ### XXX: In this block, I can emit stuff to STDOUT when an exception is
        ### raised, or something.
      end

      begin
        block.call

      rescue Exception => exception
        expected = kinds.any? {|k| exception.kind_of? k }

        case mode
        when :sample then return expected
        when :assert then expected ? passed.call : failed.call(exception)
        when :negate then expected ? failed.call(exception) : passed.call
        end

      else # nothing was raised
        case mode
        when :sample then return false
        when :assert then failed.call nil
        when :negate then passed.call
        end
      end

      exception
    end

    def assert_catch mode, symbol, message = nil, &block
      raise ArgumentError, 'block must be given' unless block

      symbol = symbol.to_sym
      message ||= "block must throw #{symbol.inspect}"

      passed = lambda { @stats[:pass] += 1 }
      failed = lambda { @stats[:fail] += 1; _debug block, message }

      # if nothing was thrown, the result of catch()
      # is simply the result of executing the block
      result = catch(symbol) do
        begin
          block.call

        rescue Exception => e
          _debug_uncaught_exception block, e unless
            # ignore error about the wrong symbol being thrown
            #
            # NOTE: Ruby 1.8 formats the thrown value in `quotes'
            #       whereas Ruby 1.9 formats it like a :symbol
            #
            e.message =~ /\Auncaught throw (`.*?'|:.*)\z/
        end

        self # unlikely that block will throw *this* object
      end

      caught = result != self
      result = nil unless caught

      case mode
      when :sample then return caught
      when :assert then caught ? passed.call : failed.call
      when :negate then caught ? failed.call : passed.call
      end

      result
    end

    ##
    # Prints the given object in YAML format.
    #
    def display object
      unless @options[:quiet]
        # stringify symbols in YAML output for better readability
        puts object.to_yaml.gsub(/^([[:blank:]]*(- )?):(?=@?\w+: )/, '\1')
      end
    end

    ##
    # Executes the current test suite recursively.
    #
    def execute
      suite = @suite
      trace = @trace

      suite.before_all.each {|b| call b }

      suite.tests.each do |test|

        suite.before_each.each {|b| call b }

        @tests.push test

        begin
          # create nested suite
          @suite = Suite.new
          @trace = []

          # populate nested suite
          call test.block, test.sandbox

          # execute nested suite
          execute

        ensure
          # restore outer values
          @suite = suite

          trace << build_exec_trace(@trace)
          @trace = trace
        end

        @tests.pop

        suite.after_each.each {|b| call b }
      end

      suite.after_all.each {|b| call b }
    end

    ##
    # Invokes the given block and debugs any
    # exceptions that may arise as a result.
    # XXX: This is where tests actually get run.
    #
    def call block, sandbox = nil
      begin
        @calls.push block

        ### XXX: This is the bit where tests actually get run.
        #
        # Example code:
        #   D "A new array" do
        #     D .< { @array = [] }
        #
        #     D "must be empty" do
        #       T { @array.empty? }
        #     end
        #
        #     D "when populated" do
        #       D .< { @array.push 55 }
        #
        #       D "must not be empty" do
        #         F { @array.empty? }
        #       end
        #     end
        #   end
        #
        # A test isn't a method like in test/unit; it's a block of code that may
        # contain assertions (T/F/Eq/...) and nested blocks.
        #
        # I think I would like to flatten the test/block structure, but that may
        # not be feasible or even desirable.
        #
        # I don't think I can exercise much control here; it's when an actual
        # assertion gets called that I can output stuff like:
        #
        #   A new array:
        #    - must be empty                  PASS
        #    - when populated:
        #      - must not be empty            PASS
        #
        # But is that really what I want to do?  This style encourages lots of
        # small tests, whereas I prefer fewer, larger ones with lots of
        # assertions.  I might rewrite the above as
        #
        #   D "Array basics" do
        #     array = []
        #     T { array.empty? }
        #     array.push 55
        #     F { array.empty? }
        #   end
        #
        # I'm not sure I care for nested contexts at all, and they make it much
        # more complicated (I think), and maybe I'd be better off starting my
        # own thing from scratch.
        #       

        debug "Description: #{@tests.last.desc}"
        $dfect_test = @tests.last.desc

        if sandbox
          sandbox.instance_eval(&block)
        else
          block.call
        end

      rescue Exception => e
        debug "Uncaught exception: #{e}"
        report_uncaught_exception block, e
        #_debug_uncaught_exception block, e

      ensure
        @calls.pop
      end
    end

    INTERNALS = File.dirname(__FILE__) # @private

    ##
    # Adds debugging information to the report.
    #
    # @param [Binding, Proc, #binding] context
    #
    #   Binding of code being debugged.  This can be either a Binding or
    #   Proc object, or nil if no binding is available---in which case,
    #   the binding of the inner-most enclosing test or hook will be used.
    #
    # @param message
    #
    #   Message describing the failure
    #   in the code being debugged.
    #
    # @param [Array<String>] backtrace
    #
    #   Stack trace corresponding to point of
    #   failure in the code being debugged.
    #
    # XXX: I'll need to come to grips with this method, for doing things like
    # extracting code and filtering the backtrace, but I'll want to simplify it
    # somewhat: farm some of the detail out to another class or something.
    #
    def _debug context, message = nil, backtrace = caller
      # inherit binding of enclosing test or hook
      context ||= @calls.last

      # allow a Proc to be passed instead of a binding
      if context and context.respond_to? :binding
        context = context.binding
      end

      # omit internals from failure details
      backtrace = backtrace.reject {|s| s.include? INTERNALS }

      # record failure details in the report
      details = {
        # user message
        :fail => message,

        # code snippet
        :code => (
          if frame = backtrace.first
            file, line = frame.scan(/(.+?):(\d+(?=:|\z))/).first

            if source = @files[file]
              line = line.to_i

              radius = 5 # number of surrounding lines to show
              region = [line - radius, 1].max ..
                       [line + radius, source.length].min

              # ensure proper alignment by zero-padding line numbers
              format = "%2s %0#{region.last.to_s.length}d %s"

              pretty = region.map do |n|
                format % [('=>' if n == line), n, source[n-1].chomp]
              end

              pretty.unshift "[#{region.inspect}] in #{file}"

              # to_yaml will render the paragraph without escaping newlines
              # ONLY IF the first and last character are non-whitespace
              pretty.join("\n").strip
            end
          end
        ),

        # variable values
        :vars => if context
          names = eval('::Kernel.local_variables + self.instance_variables', context, __FILE__, __LINE__)
            # XXX: ^^^ Here is the place to edit if I want to prevent certain
            #          variables from being printed (e.g. ignore _abc)

#         pairs = names.inject([]) do |pair, name|
#           variable = name.to_s
#           value    = eval(variable, context, __FILE__, __LINE__)
#
#           pair.push variable.to_sym, value
#         end
#         Hash[*pairs]

          names.build_hash { |name|
            variable = name.to_s
            value    = eval(variable, context, __FILE__, __LINE__)
            [variable, value]
          }
        end,

        # stack trace
        :call => backtrace,
      }

      @trace << details

      # allow user to investigate the failure
      if @options[:debug] and context
        # show only the most helpful subset of the
        # failure details, because the rest can be
        # queried (on demand) inside the debugger
        overview = details.dup
        overview.delete :vars
        overview.delete :call
        display build_fail_trace(overview)

        if Kernel.respond_to? :debugger
          eval '::Kernel.debugger', context, __FILE__, __LINE__
        else
          IRB.setup nil

          env = IRB::WorkSpace.new(context)
          irb = IRB::Irb.new(env)
          IRB.conf[:MAIN_CONTEXT] = irb.context

          catch :IRB_EXIT do
            irb.eval_input
          end
        end
      else
        # show all failure details to the user
        display build_fail_trace(details)
      end

      nil
    end  # _debug

    ### XXX: My new method for reporting a failure.
    def report_failure context, message = nil, backtrace = caller
      context ||= @calls.last
      if context and context.respond_to? :binding
        context = context.binding
      end
      debug "FAIL"
      debug "Before: #{backtrace.to_yaml}"
      backtrace = backtrace.reject {|s| s.include? INTERNALS }
      debug "After: #{backtrace.to_yaml}"

      if frame = backtrace.first
        file, line = frame.scan(/(.+?):(\d+(?=:|\z))/).first
        line = line.to_i
      end

      name_of_test = @tests.map { |t| t.desc }.join(' ')
      puts "FAIL".red.bold + ": " + name_of_test.white.bold
      puts code(file, line).indent(4) if file
      if message
        puts message.indent(2)
      else
        puts "No message! #{__FILE__}:#{__LINE__}"
        puts "See full backtrace in debug.log"
      end
      puts "  Backtrace\n" + backtrace.join("\n").indent(4)
      if vars = variables(context)
        puts "  Variables\n" + vars.indent(4)
      end
    end

    def report_uncaught_exception context, exception
      @stats[:error] += 1
      context ||= @calls.last
      if context and context.respond_to? :binding
        context = context.binding
      end
      backtrace = exception.backtrace
      debug "ERROR"
      debug "Before:\n#{backtrace.pp_s}"
      backtrace = backtrace.reject {|s| s.include? INTERNALS }
      debug "After:\n#{backtrace.pp_s}"

      if frame = backtrace.first
        file, line = frame.scan(/(.+?):(\d+(?=:|\z))/).first
        line = line.to_i
      end

      name_of_test = @tests.map { |t| t.desc }.join(' ')
      puts "ERROR".red.bold + ": " + name_of_test.white.bold
      puts code(file, line).indent(4) if file
      puts "  Message: #{exception.message.yellow.bold}"
      puts "  Backtrace\n" + backtrace.join("\n").indent(4)
      if vars = variables(context)
        puts "  Variables\n" + vars.indent(4)
      end
    end

    def code(file, line)
      if source = @files[file]
        line = line.to_i
        radius = 2 # number of surrounding lines to show
        region1 = [line - radius, 1].max .. [line - 1, 1].max
        region2 = [line]
        region3 = [line + 1, source.length].min .. [line + radius, source.length].min

        # ensure proper alignment by zero-padding line numbers
        format = "%2s %0#{region3.last.to_s.length}d %s"

        pretty1 = region1.map { |n|
          format % [nil, n, source[n-1].chomp]
        }
        pretty2 = region2.map  { |n|
          (format % ['=>', n, source[n-1].chomp]).yellow.bold
        }
        pretty3 = region3.map { |n|
          format % [nil, n, source[n-1].chomp]
        }
        pretty = pretty1 + pretty2 + pretty3

        #pretty.unshift "[#{region.inspect}] in #{file}"
        pretty.unshift file

        # to_yaml will render the paragraph without escaping newlines
        # ONLY IF the first and last character are non-whitespace
        pretty.join("\n").strip

        # XXX: But I don't care about YAML, so...
        pretty.join("\n")
      end
    end

    def variables(context)
      if context
        names = eval('::Kernel.local_variables + self.instance_variables',
                     context, __FILE__, __LINE__)
        #names = names.grep /^[a-z]/    # Ignore vars starting with underscores.
        return nil if names.empty?
        pairs = names.map { |name|
          variable = name.to_s
          value    = eval(variable, context, __FILE__, __LINE__)
          "#{variable}: #{value.inspect.truncate(40)}"
        }.join("\n")
      end
    end

    class ::String
      def truncate(n)
        str = self
        if str.length > n
          str[0...n] + "..."
        else
          str
        end
      end
    end


    ##
    # Debugs the given uncaught exception inside the given context.
    #
    def _debug_uncaught_exception context, exception
      @stats[:error] += 1
      _debug context, exception, exception.backtrace
    end

    ##
    # Returns a report that associates the given
    # failure details with the currently running test.
    #
    def build_exec_trace details
      if @tests.empty?
        details
      else
        { @tests.last.desc => details }
      end
    end

    ##
    # Returns a report that qualifies the given
    # failure details with the current test stack.
    #
    def build_fail_trace details
      @tests.reverse.inject(details) do |inner, outer|
        { outer.desc => inner }
      end
    end

    class Suite # @private
      attr_reader :tests, :before_each, :after_each, :before_all, :after_all

      def initialize
        @tests       = []
        @before_each = []
        @after_each  = []
        @before_all  = []
        @after_all   = []
      end

      Test = Struct.new(:desc, :block, :sandbox) # @private
    end
  end  # class << Dfect

  @options = {:debug => $DEBUG, :quiet => false}

  @stats  = Hash.new {|h,k| h[k] = 0 }
  @trace  = []
  @report = {:trace => @trace, :stats => @stats}.freeze

  @suite = class << self; Suite.new; end
  @share = {}
  @tests = []
  @calls = []
  @files = Hash.new {|h,k| h[k] = File.readlines(k) rescue nil }

  ##
  # Allows before and after hooks to be specified via the
  # following method syntax when this module is mixed-in:
  #
  #   D .<< { puts "before all nested tests" }
  #   D .<  { puts "before each nested test" }
  #   D .>  { puts "after  each nested test" }
  #   D .>> { puts "after  all nested tests" }
  #
  D = self

  # provide mixin-able assertion methods
  methods(false).grep(/^(x?[A-Z][a-z]?)?[<>!?]*$/).each do |name|
    #
    # XXX: using eval() on a string because Ruby 1.8's
    #      define_method() cannot take a block parameter
    #
    module_eval "def #{name}(*a, &b) ::#{self.name}.#{name}(*a, &b) end",
      __FILE__, __LINE__
    unless name =~ /[<>]/
      # Also define 'x' method that is a no-op; e.g. xD, xT, ...
      module_eval "def x#{name}(*a, &b) :no_op end", __FILE__, __LINE__
      module_eval "def Dfect.x#{name}(*a, &b) :no_op end", __FILE__, __LINE__
    end
  end

end  # module Dfect

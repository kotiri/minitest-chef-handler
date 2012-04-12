require 'minitest/unit'
require 'minitest/spec'

module MiniTest
  module Chef
    class Handler < ::Chef::Handler
      def initialize(options = {})
        path = options.delete(:path) || './test/test_*.rb'
        Dir.glob(path).each {|test_suite| require test_suite}

        @options = options
      end

      def report
        # do not run tests if chef failed
        return if failed?

        runner = Runner.new(run_status)

        if custom_runner?
          runner._run(miniunit_options)
        else
          runner.run(miniunit_options)
        end
      end

      private

      def miniunit_options
        options = []
        options << ['-n', @options[:filter]] if @options[:filter]
        options << "-v" if @options[:verbose]
        options << ['-s', @options[:seed]] if @options[:seed]
        options.flatten
      end

      # Before Minitest 2.1.0 Minitest::Unit called `run` because the custom runners support was poorly designed.
      # See: https://github.com/seattlerb/minitest/commit/6023c879cf3d5169953ee929343b679de4a48bbc
      #
      # Using this workaround we still allow to use any other runner with the test suite for versions greater than 2.1.0.
      # If the test suite doesn't use any chef injection capability it still can be ran with the default Minitest runner.
      def custom_runner?
        Gem::Version.new(MiniTest::Unit::VERSION) >= Gem::Version.new('2.1.0')
      end
    end

    class Runner < MiniTest::Unit
      attr_reader :run_status

      def initialize(run_status)
        @run_status = run_status
        super()
      end
    end

    module RunState
      attr_reader :run_status, :node, :run_context

      def run(runner)
        if runner.respond_to?(:run_status)
          @run_status = runner.run_status
          @node = @run_status.node
          @run_context = @run_status.run_context
        end
        super(runner)
      end
    end

    module Resources
      include ::Chef::Mixin::ConvertToClassName

      # Expose Chef support for loading current resource state
      def self.register_resource(resource, *required_args)
        define_method(resource) do |name, *options|
          clazz = ::Chef::Resource.const_get(convert_to_class_name(resource.to_s))
          res = clazz.new(name, run_context)
          required_args.each do |arg|
            res.send(arg, options.first[arg])
          end
          provider = ::Chef::Platform.provider_for_resource(res)
          provider.load_current_resource
          provider.current_resource
        end
      end
      register_resource(:file)
    end

    class TestCase < MiniTest::Unit::TestCase
      include MiniTest::Chef::Resources
      include MiniTest::Chef::RunState
    end

    class MiniTest::Chef::Spec < MiniTest::Spec
      include MiniTest::Chef::Resources
      include MiniTest::Chef::RunState
    end

    # MiniTest::Chef expectations will be available to specs that look like Chef recipes.
    #   describe "apache2::default" do
    MiniTest::Spec.register_spec_type(/^[a-z_\-]+\:\:[a-z_\-]+$/, MiniTest::Chef::Spec)
  end

  module Assertions

    def assert_path_exists(file_or_dir)
      assert File.exists?(file_or_dir.path)
      file_or_dir
    end

    def refute_path_exists(file_or_dir)
      refute File.exists?(file_or_dir.path)
      file_or_dir
    end

    # MiniTest::Spec
    ::Chef::Resource::File.infect_an_assertion :assert_path_exists, :must_exist, :only_one_argument
    ::Chef::Resource::File.infect_an_assertion :refute_path_exists, :wont_exist, :only_one_argument
  end

end

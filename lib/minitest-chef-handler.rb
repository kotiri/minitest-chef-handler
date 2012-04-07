require 'etc'
require 'minitest/unit'
require 'minitest/spec'

# Ensure that all notifications are handled before exiting. This is preferable
# to raising or exiting from our handler and breaking other handlers.
Chef::Client.class_eval do
  class << self
    attr_accessor :exit_error
  end

  alias :old_run_completed_successfully :run_completed_successfully

  def run_completed_successfully
    old_run_completed_successfully
    exit_error = Chef::Client.exit_error
    Chef::Application.fatal!(exit_error[:message], exit_error[:code]) if exit_error
  end
end

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
        test_failures = runner._run(miniunit_options)
        ensure_ci_fails_build if test_failures > 0
      end

      private

      def ensure_ci_fails_build
        if ::Chef::Config[:solo]
          ::Chef::Client.exit_error =
            {:message => 'There were test failures', :code => 3}
        end
      end

      def miniunit_options
        options = []
        options << ['-n', @options[:filter]] if @options[:filter]
        options << "-v" if @options[:verbose]
        options << ['-s', @options[:seed]] if @options[:seed]
        options.flatten
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

      def ran_recipe?(recipe)
        node.run_state[:seen_recipes].keys.include?(recipe)
      end

      def run(runner)
        if runner.respond_to?(:run_status)
          @run_status = runner.run_status
          @node = @run_status.node
          @run_context = @run_status.run_context
          return unless ran_recipe?(self.class.name)
        end
        super(runner)
      end
    end

    module Resources
      include ::Chef::Mixin::ConvertToClassName

      def self.register_resource(resource)
        define_method(resource) do |name|
          clazz = ::Chef::Resource.const_get(convert_to_class_name(resource.to_s))
          res = clazz.new(name, run_context)
          ::Chef::Platform.provider_for_resource(res).load_current_resource
        end
      end
      [:directory, :file, :package, :service].each{|r| register_resource(r)}

      ::Chef::Resource.class_eval do
        include MiniTest::Assertions
        def with(attribute, values)
          if attribute == :mode
            assert_equal values, mode.kind_of?(Integer) ? mode.to_s(8) : mode.to_s
          elsif [:owner, :user].include?(attribute)
            assert_equal values, Etc.getpwuid(owner).name
          else
            assert_equal values, send(attribute)
          end
          self
        end
        alias :and :with
        alias :must_have :with
      end

      ::Chef::Resource::File.class_eval do
        def include?(obj)
          File.read(@path).include?(obj)
        end
      end
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
    MiniTest::Spec.register_spec_type(/^[a-z_]+\:\:[a-z_]+$/, MiniTest::Chef::Spec)
  end

  module Assertions

    def assert_exists(file_or_dir)
      assert File.exists?(file_or_dir.path)
      file_or_dir
    end

    def refute_exists(file_or_dir)
      refute File.exists?(file_or_dir.path)
      file_or_dir
    end

    def assert_installed(package)
      refute package.version.nil?, "Expected package '#{package.name}' to be installed"
      package
    end

    def refute_installed(package)
      assert package.version.nil?, "Expected package '#{package.name}' to not be installed"
      installed
    end

    def assert_running(service)
      assert service.running, "Expected service '#{service.name}' to be running"
      service
    end

    def refute_running(service)
      refute service.running, "Expected service '#{service.name}' to not be running"
      service
    end

    def assert_enabled(service)
      assert service.enabled, "Expected service '#{service.name}' to be enabled"
      service
    end

    def refute_enabled(service)
      refute service.enabled, "Expected service '#{service.name}' to be disabled"
      service
    end

    # MiniTest::Spec
    ::Chef::Resource::Directory.infect_an_assertion :assert_exists, :must_exist, :only_one_argument
    ::Chef::Resource::Directory.infect_an_assertion :refute_exists, :wont_exist, :only_one_argument
    ::Chef::Resource::File.infect_an_assertion :assert_exists, :must_exist, :only_one_argument
    ::Chef::Resource::File.infect_an_assertion :refute_exists, :wont_exist, :only_one_argument
    ::Chef::Resource::Service.infect_an_assertion :assert_running, :must_be_running, :only_one_argument
    ::Chef::Resource::Service.infect_an_assertion :refute_running, :wont_be_running, :only_one_argument
    ::Chef::Resource::Service.infect_an_assertion :assert_enabled, :must_be_enabled, :only_one_argument
    ::Chef::Resource::Service.infect_an_assertion :refute_enabled, :wont_be_enabled, :only_one_argument
    ::Chef::Resource::Package.infect_an_assertion :assert_installed, :must_be_installed, :only_one_argument
    ::Chef::Resource::Package.infect_an_assertion :refute_installed, :wont_be_installed, :only_one_argument
  end

end

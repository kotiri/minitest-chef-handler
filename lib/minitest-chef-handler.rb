require 'minitest/spec'
require 'minitest/unit'

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
        runner._run(miniunit_options)
      end

      private
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
    MiniTest::Spec.register_spec_type(/^[a-z_]+\:\:[a-z_]+$/, MiniTest::Chef::Spec)

  end

  module Assertions

    def assert_exists(file_or_dir)
      assert File.exists?(file_or_dir.path)
    end

    def refute_exists(file_or_dir)
      refute File.exists?(file_or_dir.path)
    end

    def assert_installed(package)
      refute package.version.nil?, "Expected package '#{package.name}' to be installed"
    end

    def refute_installed(package)
      assert package.version.nil?, "Expected package '#{package.name}' to not be installed"
    end

    def assert_running(service)
      assert service.running, "Expected service '#{service.name}' to be running"
    end

    def refute_running(service)
      refute service.running, "Expected service '#{service.name}' to not be running"
    end

    def assert_enabled(service)
      assert service.enabled, "Expected service '#{service.name}' to be enabled"
    end

    def refute_enabled(service)
      refute service.enabled, "Expected service '#{service.name}' to be disabled"
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

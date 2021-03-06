# -*- encoding: utf-8 -*-
Gem::Specification.new do |gem|
  gem.authors       = ["David Calavera"]
  gem.email         = ["david.calavera@gmail.com"]
  gem.description   = %q{Run Minitest suites as Chef report handlers}
  gem.summary       = %q{Run Minitest suites as Chef report handlers}
  gem.homepage      = ""

  gem.executables   = `git ls-files -- bin/*`.split("\n").map{ |f| File.basename(f) }
  gem.files         = `git ls-files`.split("\n")
  gem.test_files    = `git ls-files -- {test,spec,features}/*`.split("\n")
  gem.name          = "minitest-chef-handler"
  gem.require_paths = ["lib"]
  gem.version       = '0.3.0'

  gem.add_dependency('chef')
  gem.add_development_dependency('rake')
end

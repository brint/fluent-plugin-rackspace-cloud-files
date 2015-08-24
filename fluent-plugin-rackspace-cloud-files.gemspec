# encoding: utf-8
$LOAD_PATH.push File.expand_path('../lib', __FILE__)

Gem::Specification.new do |gem|
  gem.name        = 'fluent-plugin-rackspace-cloud-files'
  gem.description = 'Rackspace Cloud Files output plugin for Fluent event '\
                    'collector'
  gem.homepage    = 'https://github.com/brint/fluent-plugin-rackspace-cloud-files'
  gem.summary     = 'Rackspace Cloud Files output plugin for fluentd'
  gem.version     = File.read('VERSION').strip
  gem.authors     = ['Brint O\'Hearn']
  gem.email       = 'brintly@gmail.com'
  gem.license     = 'Apache License 2.0'
  gem.has_rdoc    = false
  gem.files       = `git ls-files`.split("\n")
  gem.test_files  = `git ls-files -- {test,spec,features}/*`.split("\n")
  gem.executables = `git ls-files -- bin/*`.split("\n").map do |f|
    File.basename(f)
  end
  gem.require_paths = ['lib']

  gem.add_runtime_dependency 'fluentd', '~> 0.12.12', '>= 0.12.12'
  gem.add_runtime_dependency 'fog', '~> 1.33', '>= 1.33.0'
  gem.add_runtime_dependency 'yajl-ruby', '~> 1.2', '>= 1.2.1'
  gem.add_runtime_dependency 'fluent-mixin-config-placeholders', '~> 0.3.0',
                             '>= 0.3.0'
  gem.add_development_dependency 'rake', '~> 10.1', '>= 10.1.0'
  gem.add_development_dependency 'flexmock', '~> 1.2', '>= 1.2.0'
  gem.add_development_dependency 'rubocop', '~> 0.33.0', '>= 0.33.0'
end

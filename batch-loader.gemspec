# coding: utf-8
require_relative "./lib/batch_loader/version"

Gem::Specification.new do |spec|
  spec.name          = "batch-loader"
  spec.version       = BatchLoader::VERSION
  spec.authors       = ["exAspArk"]
  spec.email         = ["exaspark@gmail.com"]

  spec.summary       = %q{Powerful tool to avoid N+1 DB or HTTP queries}
  spec.description   = %q{Powerful tool to avoid N+1 DB or HTTP queries}
  spec.homepage      = "https://github.com/exAspArk/batch-loader"
  spec.license       = "MIT"

  spec.files         = `git ls-files -z`.split("\x0").reject do |f|
    f.match(%r{^(spec|images)/})
  end
  spec.bindir        = "exe"
  spec.executables   = spec.files.grep(%r{^exe/}) { |f| File.basename(f) }
  spec.require_paths = ["lib"]

  spec.required_ruby_version = '>= 2.1.0' # keyword args

  spec.add_development_dependency "bundler", "~> 1.15"
  spec.add_development_dependency "rake", "~> 10.0"
  spec.add_development_dependency "rspec", "~> 3.0"
  spec.add_development_dependency "graphql", "~> 1.6"
  spec.add_development_dependency "pry-byebug", "~> 3.4"
  spec.add_development_dependency "benchmark-ips", "~> 2.7"
  spec.add_development_dependency "ruby-prof", "~> 0.16"
end

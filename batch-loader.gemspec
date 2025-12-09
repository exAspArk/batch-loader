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
    f.match(%r{^(spec|images)/}) || f == "Makefile"
  end
  spec.bindir        = "exe"
  spec.executables   = spec.files.grep(%r{^exe/}) { |f| File.basename(f) }
  spec.require_paths = ["lib"]

  spec.required_ruby_version = '>= 2.1.0' # keyword args

  spec.add_development_dependency "bundler", "~> 2.0"
  spec.add_development_dependency "rake", "~> 13.0"
  spec.add_development_dependency "rspec", "~> 3.0"
  spec.add_development_dependency "graphql", "~> 1.8"
  spec.add_development_dependency "pry", "~> 0.14"
  spec.add_development_dependency "benchmark-ips", "~> 2.7"
  spec.add_development_dependency "ruby-prof", "~> 0.16"
end

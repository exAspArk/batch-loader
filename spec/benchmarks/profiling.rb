# frozen_string_literal: true

# Usage: ruby spec/benchmarks/profiling.rb

require 'ruby-prof'

require_relative "../../lib/batch_loader"
require_relative "../fixtures/models"

User.save(id: 1)

def batch_loader
  BatchLoader.for(1).batch do |ids, loader|
    User.where(id: ids).each { |user| loader.call(user.id, user) }
  end
end

RubyProf.measure_mode = RubyProf::WALL_TIME
RubyProf.start

1_000.times { batch_loader.id }

result = RubyProf.stop
stack_printer = RubyProf::CallStackPrinter.new(result)
File.open("tmp/stack.html", 'w') { |file| stack_printer.print(file) }

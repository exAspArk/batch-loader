# frozen_string_literal: true

# Usage: ruby spec/benchmarks/graphql.rb && open tmp/stack.html

require 'ruby-prof'
require "graphql"

require_relative "../../lib/batch_loader"
require_relative "../fixtures/models"
require_relative "../fixtures/graphql_schema"

iterations = Array.new(2_000)

iterations.each_with_index do |_, i|
  user = User.save(id: i)
  Post.save(user_id: user.id)
end

query = "{ posts { user { id } } }"

RubyProf.measure_mode = RubyProf::WALL_TIME
RubyProf.start

GraphqlSchema.execute(query) # 0.45, 0.52, 0.47 sec

result = RubyProf.stop
stack_printer = RubyProf::CallStackPrinter.new(result)
File.open("tmp/stack.html", 'w') { |file| stack_printer.print(file) }

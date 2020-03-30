require "rake/testtask.rb"
require 'rake'

Rake::TestTask.new do |t|
  t.libs << "test"
  t.test_files = FileList['test/test_*.rb'] + FileList['test/plugins/test_*.rb']
  t.verbose = true
end

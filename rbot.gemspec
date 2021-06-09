require 'rake'

Gem::Specification.new do |s|
  s.name = 'rbot'
  s.version = '0.9.15'
  s.summary = <<-EOF
    A modular ruby IRC bot.
  EOF
  s.description = <<-EOF
    A modular ruby IRC bot specifically designed for ease of extension via plugins.
  EOF
  s.requirements << 'Ruby, version 1.9.3 (or newer)'
  s.licenses = ['GPL-2.0']

  s.files = FileList[
	  'lib/**/*.rb',
	  'bin/*',
	  'data/rbot/**/*',
	  'AUTHORS',
	  'COPYING',
	  'COPYING.rbot',
	  'GPLv2',
	  'README.md',
	  'REQUIREMENTS',
	  'TODO',
	  'ChangeLog',
	  'INSTALL',
	  'Usage_en.txt',
	  'man/rbot.xml',
	  'man/rbot-remote.xml',
	  'setup.rb',
	  'launch_here.rb',
	  'po/*.pot',
	  'po/**/*.po'
  ]

  s.bindir = 'bin'
  s.executables = ['rbot', 'rbotdb', 'rbot-remote']
  s.extensions = 'Rakefile'

  s.rdoc_options = ['--exclude', 'post-install.rb',
  '--title', 'rbot API Documentation', '--main', 'README.rdoc', 'README.rdoc']

  s.author = 'Tom Gilbert'
  s.email = 'tom@linuxbrit.co.uk'
  s.homepage = 'https://ruby-rbot.org'

end


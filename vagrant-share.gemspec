Gem::Specification.new do |s|
  version = File.read(File.expand_path("../version.txt", __FILE__)).chomp

  s.name          = "vagrant-share"
  s.version       = version
  s.platform      = Gem::Platform::RUBY
  s.authors       = ["Mitchell Hashimoto", "Vagrant Team"]
  s.email         = "vagrant@hashicorp.com"
  s.homepage      = "http://www.vagrantup.com"
  s.summary       = "Provides share functionality to Vagrant"
  s.description   = "Provides share functionality to Vagrant"
  s.license       = "MPL-2.0"

  s.add_dependency "rest-client", ">= 1.6.0"
  s.add_dependency "vagrant", ">= 1.9.2"

  root_path      = File.dirname(__FILE__)
  all_files      = Dir.chdir(root_path) { Dir.glob("lib/**/*") }
  all_files      += ["version.txt"]
  all_files.concat(Dir.chdir(root_path) { Dir.glob("locales/**/*") })
  all_files.reject! { |file| [".", ".."].include?(File.basename(file)) }

  gitignore_path = File.join(root_path, ".gitignore")
  gitignore      = File.readlines(gitignore_path)
  gitignore.map!    { |line| line.chomp.strip }
  gitignore.reject! { |line| line.empty? || line =~ /^(#|!)/ }

  unignored_files = all_files.reject do |file|
    next true if File.directory?(file)
    gitignore.any? do |ignore|
      File.fnmatch(ignore, file, File::FNM_PATHNAME) ||
        File.fnmatch(ignore, File.basename(file), File::FNM_PATHNAME)
    end
  end

  s.files         = unignored_files
  s.executables   = []
  s.require_path  = 'lib'
end

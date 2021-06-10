source "https://rubygems.org"

group :development, :testing do
  if File.exist?(File.expand_path("../../vagrant", __FILE__))
    gem "vagrant", path: "../vagrant"
  elsif ENV["VAGRANT_PATH"]
    gem "vagrant", path: ENV["VAGRANT_PATH"]
  else
    gem "vagrant", git: "git://github.com/mitchellh/vagrant.git"
  end

  gem "vagrant-spec", git: "https://github.com/hashicorp/vagrant-spec.git", branch: "main"
  gem "rake"
  gem "rspec"
  gem "rspec-its"
end

group :plugins do
  gem "vagrant-share", path: "."
end

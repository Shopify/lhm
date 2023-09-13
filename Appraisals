# Oldest supported Rails version
appraise "activerecord-5.2" do
  gem "activerecord", "5.2.6"

# This gemfile will be ran against ruby 2.4 and some gems might require 2.4+. The following list are the gems
# and their respective versions that work with ruby <= 2.4
  gem "simplecov", "0.18.5"
  gem "docile", "1.3.5"
end

# First conflicted version
appraise "activerecord-6.0" do
  gem "activerecord", "6.0.0"
end

# Second conflicted version
appraise "activerecord-6.1" do
  gem "activerecord", "6.1.0"
end

# Latest version at the moment
appraise "activerecord-7.0" do
  gem "activerecord", "7.0.8"
end

# Next release
appraise "activerecord-7.1.0.beta1" do
  gem "activerecord", "7.1.0.beta1"
end
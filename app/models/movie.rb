class Movie < ActiveRecord::Base
  validates_uniqueness_of :title, :scope => [:year, :runtime, :genres]
end

# This file should contain all the record creation needed to seed the database with its default values.
# The data can then be loaded with the rake db:seed (or created alongside the db with db:setup).
#
# Created 1/14/18

require 'open-uri'
require 'zlib'
require 'date'
require 'mechanize'
require 'activerecord-import'

# StrictTsv helper class. The main parse method is mostly borrowed from a tweet by @JEG2
class StrictTsv
  attr_reader :filepath
  def initialize(filepath)
    @filepath = filepath
  end

  def parse
    open(filepath) do |f|
      headers = f.gets.strip.split("\t")
      f.each do |line|
        fields = Hash[headers.zip(line.split("\t"))]
        yield fields
      end
    end
  end
end

# Helper function to parse a tsv file line by line into the movies table of the database.
def parse_tsv_into_database(tsv)
  i = 1
  movies_to_import = Array.new
  puts 'Populating the database with the movies. This may take a while...'
  puts 'Starting at ' + DateTime.now.rfc3339
  tsv.parse do |row|
    # Check the conditions before adding to the database. That is, ensure that the entry is A. a movie, and B. not an adult film
    if row[@tsv_columns[:type]] == "movie" && row[@tsv_columns[:adult]] == '0'
      # Store the information about the movie into a movie object, and add it to the array to be later imported
      movie = Movie.new
      movie.title = row[@tsv_columns[:title]]
      movie.year = row[@tsv_columns[:year]]
      movie.runtime = row[@tsv_columns[:runtime]]
      movie.genres = row[@tsv_columns[:genres]].chomp
      movies_to_import << movie
      puts 'Prepared movie number ' + i.to_s
      i = i + 1
    end
  end
  puts 'Finished preparing the movies. Now adding the movies to the database.'
  Movie.import movies_to_import
end

# Variables
@url = 'https://datasets.imdbws.com/title.basics.tsv.gz'
@archive_file_name = Rails.root.join 'db', 'title.basics.tsv.gz'
@data_file_name = Rails.root.join 'db', 'data.tsv'
@tsv_columns = {
  :type => "titleType",
  :title => "primaryTitle",
  :adult => "isAdult",
  :year => "startYear",
  :runtime => "runtimeMinutes",
  :genres => "genres"
}

# Check if the files already exist. If so, delete it and redownload -- we want the most recent version.
File.delete@archive_file_name if File.file? @archive_file_name
File.delete @data_file_name if File.file? @data_file_name

# Download the file, printing status messages before and after
puts 'Downloading the movie database archive. This may take a few minutes.'
#File.write @archive_file_name, open(@url).read
agent = Mechanize.new
agent.pluggable_parser.default = Mechanize::Download
agent.get(@url).save(@archive_file_name)
puts 'Finished downloading the movie database archive.'

# Unzip the downloaded file
puts 'Extracting the archive.'
output_file = File.open(@data_file_name, 'w')
gz_extract = Zlib::GzipReader.open(@archive_file_name)
gz_extract.each_line do |extract|
  output_file.write(extract)
end
output_file.close
puts 'Finished extracting the archive.'

# Create the tsv object and parse the file into the database.
tsv = StrictTsv.new @data_file_name
parse_tsv_into_database tsv

# Alert the user that the database population is finished.
puts 'Finished populating the film database.'
puts 'Finished at ' + DateTime.now.rfc3339

# Cleanup -- delete the now unnecessary archive/data files
File.delete@archive_file_name if File.file? @archive_file_name
File.delete @data_file_name if File.file? @data_file_name

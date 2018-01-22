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

# Helper function to split a tsv into several tsvs, each containing less than 50000 lines.
# Returns an array containing the file names of each sub tsv
def split_tsv(tsv_file_name)
  main_file = File.open tsv_file_name
  # Get the headers and store them for later
  headers = main_file.gets
  # Count the number of lines in the file
  length_of_file = 0
  main_file.each_line do
    length_of_file += 1
  end
  main_file.close
  # Split the main tsv into several smaller tsvs. First figure out how many.
  number_of_tsvs = ((length_of_file.to_f)/(50000.to_f)).ceil
  sub_tsvs = Array.new
  file_names = Array.new
  # Create each file and write the headers to each
  number_of_tsvs.times do |i|
    file_name = Rails.root.join('db', 'subsets', 'data_' + (i+1).to_s + '.tsv')
    file_names << file_name
    # Delete the sub file if it already exists and regenerate
    File.delete file_name if File.file? file_name
    tsv = File.open file_name, 'w'
    tsv.write headers
    sub_tsvs << tsv
  end
  # Write 50000 lines to each file
  i = 0
  main_file = File.open tsv_file_name
  main_file.each_line do |line|
    sub_tsvs[((i.to_f)/(50000.to_f)).floor].write line if i > 0
    i += 1
  end
  # Close each sub tsv file
  sub_tsvs.each do |file|
    file.close
  end
  # Return the list of file names
  file_names
end

# Helper function to serve as a comparator for the sort_and_remove_duplicates function.
def compare_movies movie1, movie2
  # First compare the titles of the movies
  if (movie1.title.downcase <=> movie2.title.downcase) == 0
    if (movie1.year <=> movie2.year) == 0
      if (movie1.runtime <=> movie2.runtime) == 0
        movie1.genres.downcase <=> movie2.genres.downcase
      else
        movie1.runtime <=> movie2.runtime
      end
    else
      movie1.year <=> movie2.year
    end
  else
    movie1.title.downcase <=> movie2.title.downcase
  end
end

# Sorts a list of movie objects
def sort(movies)
  # Sort the list. The movies will be sorted first by title, then year, then runtime, then genres.
  movies.sort! { |a, b| compare_movies a, b }

  # Lastly, return the subset of movies
  movies
end

# Removes duplicates from the list of movie objects. The list must be sorted before calling this function.
def remove_duplicates(movies)
  # Iterate through the list and remove any duplicates -- they should be right next to each other
  i = 0
  while i < (movies.length - 1)
    if compare_movies(movies[i], movies[i+1]) == 0
      movies.delete_at i
    else
      i += 1
    end
  end

  # Lastly, return the subset of movies
  movies
end

# Reads in the data from a sub tsv file, creates an array of movie objects and returns it
def read_from_tsv(tsv)
  puts "Thread #{tsv.filepath} is starting:"
  # First read in the data from the file
  movies = Array.new
  tsv.parse do |row|
    # Check the conditions before creating the object. That is, ensure the entry is both a movie and not an adult film.
    if row[@tsv_columns[:type]] == "movie" && row[@tsv_columns[:adult]] == '0'
      # Store the information about the movie into a movie object, and add it to the array to be later imported
      movie = Movie.new
      movie.title = row[@tsv_columns[:title]]
      movie.year = row[@tsv_columns[:year]]
      movie.runtime = row[@tsv_columns[:runtime]]
      movie.genres = row[@tsv_columns[:genres]].chomp
      movies << movie
    end
  end
  # Return the list of movies
  movies

end

# Helper function to merge sets of movies. Uses the merge subroutine from mergesort, along with a check to make sure the
# most recently added movie is not being added again.
def merge_sets(set1, set2)
  merged_set = Array.new
  last_movie_added = Movie.new
  while set1.length > 0 && set2.length > 0
    test = compare_movies set1[0], set2[0]
    if test == -1
      if (compare_movies set1[0], last_movie_added) != 0
        merged_set << set1[0]
      end
      set1.delete_at 0
    elsif test == 1
      if (compare_movies set2[0], last_movie_added) != 0
        merged_set << set2[0]
      end
      set2.delete_at 0
    else
      if (compare_movies set1[0], last_movie_added) != 0
        merged_set << set1[0]
      end
      set1.delete_at 0
      set2.delete_at 0
    end
  end
  if set1.length > 0
    while set1.length > 0
      merged_set << set1[0]
      set1.delete_at 0
    end
  elsif set2.length > 0
    while set2.length > 0
      merged_set << set2[0]
      set2.delete_at 0
    end
  end
  merged_set
end

def combine_all_subsets(subsets)
  # Remove the empty subsets
  subsets.delete_if {|subset| subset.length == 0}

  # Print some useful information to the user
  puts 'Now merging the subsets.'
  sum = 0
  subsets.each do |set|
    puts 'set empty' if set.length == 0
    sum += set.length
  end
  puts "Total number of movies before merging sets: #{sum}"
  puts "Total number of subsets of movies before merging sets: #{subsets.length}"

  # Merge all of the subsets into one subset
  while subsets.length > 1
    puts 'Launching one iteration of merging.'
    temp = Array.new
    # If there is an odd number of subsets, pull one out
    if subsets.length % 2 == 1
      temp << subsets[0]
      subsets.delete_at 0
    end
    # Pull the subsets out in pairs, merge them and add them back to temp as one subset
    while subsets.length > 0
      set1 = subsets[0]
      subsets.delete_at 0
      set2 = subsets[0]
      subsets.delete_at 0
      temp << merge_sets(set1, set2)
    end
    # Copy the temp array back to the subsets array
    temp.each do |set|
      subsets << set
    end
  end

  # Return the movies in the one remaining subset
  subsets[0]
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
#File.delete @data_file_name if File.file? @data_file_name

# Download the file, printing status messages before and after
# puts 'Downloading the movie database archive. This may take a few minutes.'
# #File.write @archive_file_name, open(@url).read
# agent = Mechanize.new
# agent.pluggable_parser.default = Mechanize::Download
# agent.get(@url).save(@archive_file_name)
# puts 'Finished downloading the movie database archive.'
#
# # Unzip the downloaded file
# puts 'Extracting the archive.'
# output_file = File.open(@data_file_name, 'w')
# gz_extract = Zlib::GzipReader.open(@archive_file_name)
# gz_extract.each_line do |extract|
#   output_file.write(extract)
# end
# output_file.close
# puts 'Finished extracting the archive.'

# Split the tsv file and get the names of the separate files
file_names = split_tsv @data_file_name

# Create the subsets of the list of movies and sort them all, removing duplicates as well
subsets = Array.new
file_names.each do |file_name|
  tsv = StrictTsv.new file_name
  subsets << remove_duplicates(sort(read_from_tsv(tsv)))
end

# Combine all the subsets
movies_scraped = combine_all_subsets subsets

# Get a list of all movies currently in the database and sort it
movies_in_database = Array.new
Movie.all.each do |movie|
  movies_in_database << movie
end
movies_in_database = sort movies_in_database

puts "Number of movies scraped: #{movies_scraped.length}"
puts "Number of movies already in database: #{movies_in_database.length}"


# Create the tsv object and parse the file into the database.
#tsv = StrictTsv.new @data_file_name
#parse_tsv_into_database tsv

# Alert the user that the database population is finished.
puts 'Finished populating the film database.'
puts 'Finished at ' + DateTime.now.rfc3339

# Cleanup -- delete the now unnecessary archive/data files
File.delete@archive_file_name if File.file? @archive_file_name
#File.delete @data_file_name if File.file? @data_file_name

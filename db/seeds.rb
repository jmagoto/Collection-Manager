# This file should contain all the record creation needed to seed the database with its default values.
# The data can then be loaded with the rake db:seed (or created alongside the db with db:setup).
#
# Created 1/14/18

require 'open-uri'

# Variable to hold the url where the movie data is stored
@url = 'https://datasets.imdbws.com/title.basics.tsv.gz'
@archive_file_name = 'title.basics.tsv.gz'

# Download the file, printing status messages before and after
puts 'Downloading the movie database. This may take a few minutes.'
File.write @archive_file_name, open(@url).read
puts 'Finished downloading the movie database.'
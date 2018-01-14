# This file should contain all the record creation needed to seed the database with its default values.
# The data can then be loaded with the rake db:seed (or created alongside the db with db:setup).
#
# Created 1/14/18

require 'open-uri'
require 'zlib'

# Variables
@url = 'https://datasets.imdbws.com/title.basics.tsv.gz'
@archive_file_name = 'title.basics.tsv.gz'
@data_file_name = 'data.tsv'

# Check if the files already exist. If so, delete it and redownload -- we want the most recent version.
File.delete@archive_file_name if File.file? @archive_file_name
File.delete @data_file_name if File.file? @data_file_name

# Download the file, printing status messages before and after
puts 'Downloading the movie database archive. This may take a few minutes.'
File.write @archive_file_name, open(@url).read
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
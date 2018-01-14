class AddGenresToMovies < ActiveRecord::Migration
  def change
    add_column :movies, :genres, :string
  end
end

require 'open-uri'
require 'tmpdir'

@books = { 
  moby_dick: 'http://www.gutenberg.org/cache/epub/2701/pg2701.txt',
  bible: 'http://www.gutenberg.org/cache/epub/10/pg10.txt',
  war_and_peace: 'http://www.gutenberg.org/cache/epub/2600/pg2600.txt',
  ulysses: 'http://www.gutenberg.org/cache/epub/4300/pg4300.txt'
}

@book_dir = File.join(Dir.tmpdir, 'flux_test_files')

def local_book_file(title)
  File.join(@book_dir, "#{title}.txt")
end

def bootstrap_book_files
  Dir.mkdir(@book_dir) rescue nil
  @books.each do |title, book_url|
    next if File.exists?(local_book_file(title))
    puts "One-time download of #{title} locally..."
    open(local_book_file(title), 'wb') do |file|
      file << open(book_url).read
    end
  end
end

def words_from_book(book_name)
  File.open(local_book_file(book_name)).read.split
end


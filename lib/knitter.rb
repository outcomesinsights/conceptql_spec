require "conceptql"
require "sequelizer"
require "digest"
require_relative "annotater"
require_relative "annotate_grapher"

class Knitter
  include Sequelizer

  attr :cdb, :file, :options

  CONCEPTQL_CHUNK_START = /```ConceptQL/
  RESULT_KEYS = %i(person_id criterion_id criterion_domain start_date end_date source_value)

  def initialize(file, options = {})
    @file = Pathname.new(file)
    raise "File must end in .cql.md!" unless file =~ /\.cql\.md$/
    @cdb = ConceptQL::Database.new(db)
    @options = options.dup
  end

  def knit
    lines = file.readlines
    chunks = lines.slice_before { |l| l =~ CONCEPTQL_CHUNK_START }.to_a
    outputs = []
    outputs << chunks.shift unless chunks.first.first =~ CONCEPTQL_CHUNK_START
    outputs += chunks.map.with_index do |chunk, i|
      cql, *remainder = chunk.slice_after { |l| l =~ /^```\n$/ }.to_a
      cql = ConceptQLChunk.new(cql, cache, i + 1, self)
      [cql.output, remainder].flatten
    end.flatten
    File.write(file.to_s.sub(/\.cql/, ''), outputs.join)
  end

  def diagram_dir
    @diagram_dir ||= (dir + file.basename('.cql.md')).tap { |d| d.rmtree if d.exist? ; d.mkpath }
  end

  def diagram_relative_path
    @diagram_relative_path ||= diagram_dir.basename
  end

  def diagram_path(stmt, &block)
    png_contents = cache.fetch_or_create(stmt.inspect, &block)
    file_name = (cache.hash_it(stmt) + ".png")
    new_path = (diagram_dir + file_name)
    new_path.write(png_contents)
    diagram_relative_path + file_name
  end

  def query(stmt)
    cdb.query(stmt)
  end

  private
  class ConceptQLChunk
    attr :lines, :cache, :number, :knitter
    def initialize(lines, cache, number, knitter)
      @cache = cache
      @lines = lines.to_a
      @number = number
      @knitter = knitter
      @options_line = lines.first.dup
    end

    def output
      diagram_markup
      cache.fetch_or_create(lines.join) do
        create_output
      end
    end

    def titleize(title)
      return '' unless title
      title.map(&:strip).join(" ").gsub(/#\s*/, '')
    end

    def make_statement_and_title
      lines.shift
      lines.pop
      title, statement = lines.slice_after { |l| l =~ /^\s*#/ }.to_a
      if statement.nil?
        statement = title
        title = nil
      end
      @statement = eval(statement.join)
      @title = titleize(title)
    end

    def options
      @options ||= eval(@options_line.gsub(CONCEPTQL_CHUNK_START, '')) || {}
    end

    def statement
      @statement || make_statement_and_title
      @statement
    end

    def title
      @title || make_statement_and_title
      @title
    end

    def create_output
      output = []
      output << "---"
      output << ''
      unless title.empty?
        output << "**Example #{number} - #{title}**"
      else
        output << "**Example #{number}**"
      end
      output << ''
      output << "```JSON"
      output << ''
      output << statement.to_json
      output << ''
      output << "```"
      output << ''
      output << diagram_markup
      output << ''
      output << table
      output << ''
      output << "---"
      output << ''
      output.compact.join("\n")
    end

    def diagram_markup
      diagram_path = diagram(statement)
      return "![#{title}](#{diagram_path})" if diagram_path
      nil
    end

    def table
      results = nil
      begin
        results = knitter.cdb.query(statement).query.limit(10).all
      rescue
        puts $!.message
        puts $!.backtrace.join("\n")
      end

      if results.nil?
        "```No Results.  Statement is experimental.```"
      else
        if results.empty?
          "```No Results found.```"
        else
          resultify(results)
        end
      end
    end

    def resultify(results)
      rows = []
      keys = RESULT_KEYS
      keys = results.first.keys if options[:all_keys]
        
      rows << rowify(keys)
      rows << rowify(keys.map { |c| c.to_s.gsub(/./, '-')})
      results.each do |result|
        rows << rowify(result.values_at(*keys))
      end
      rows.join("\n")
    end

    def rowify(columns)
      "| #{columns.join(" | ")} |"
    end

    def diagram(stmt)
      knitter.diagram_path(stmt) do |path_name|
        annotated = Annotater.new(knitter.cdb, stmt).annotate
        AnnotateGrapher.new.graph_it(annotated, path_name, output_type: 'png')
      end
    end
  end

  class Cache
    attr :options, :file

    def initialize(file, options = {})
      @file = file
      @options = options.nil? ? {} : options.dup
      remove_cache if @options[:ignore]
    end

    def remove_cache
      cache_dir.rmtree
      @cache_dir = nil
    end

    def cache_file_path(str)
      cache_dir + hash_it(str)
    end

    def fetch_or_create(str, &block)
      cache_file = cache_file_path(str)
      return cache_file.read if cache_file.exist?
      p ["cache miss for", str, cache_file]
      output = block.call(cache_file)
      cache_file.write(output) unless cache_file.exist?
      cache_file.read
    end

    def cache_dir
      @cache_dir ||= (file.dirname + ".#{hash_it(hash_fodder)}").tap { |d| d.mkpath }
    end

    def hash_fodder
      (ENV["SEQUELIZER_URL"] + file.basename.to_s)
    end

    def hash_it(str)
      Digest::SHA256.hexdigest("#{str}")
    end
  end

  def dir
    file.dirname
  end

  def cache
    @cache ||= Cache.new(file, options[:cache_options])
  end
end